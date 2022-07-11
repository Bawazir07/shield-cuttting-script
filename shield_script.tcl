###############################################################################
##       1. Find shielding shorts                                            ##
##       2. Remove shielding shorts                                          ##
##                                                                           ##
##       Created by: maaz                                                    ##
##                                                                           ##
###############################################################################

### Look through each shield net

proc mk_get_coords4bbox {pin_bbox} {
    regsub -all {\{} $pin_bbox " " pin_bbox
    regsub -all {\}} $pin_bbox " " pin_bbox
    regsub -all "\s+" $pin_bbox " " pin_bbox
    lassign $pin_bbox px1 py1 px2 py2
    return "$px1 $py1 $px2 $py2"
}


proc find_pwr_shorts {layer remove} {
    set layer "M15"
    set nettype "power"
    print_info "Finding shielding shorts on layer $layer "
    set m15_space "0.140"
    #Old way of writing -> set partition ${::env(DBB)}
    set partition ${::env(block)}
    set area [pwd]
    set infile [open "${partition}_pwrshort.rpt" w+]
    set infile_0 [open "${partition}_pwrshort_rm.tcl" w+]

    set num_shorts 0
    puts $infile "Layer | Shield Name |  Shield Shape  |  Power Name |   Power Shape |   Shield Bbox    |    Power Bbox    |    Intersect    | Removal "
    set candidate_shapes [get_shapes *  -filter "layer_name==${layer} && (shape_use==detail_route || shape_use==user_route || shape_use==shield_route ) && (net_type==ground)"]
#Collection of Vss
    foreach_in_collection shape_tmp [get_shapes $candidate_shapes] {
        set shape_name [ga [get_shapes $shape_tmp] full_name]
        set shape_owner [get_object_name [ga [get_shapes $shape_name] owner ]]  
        set shape_bbox [ga [get_shapes $shape_name] bbox ]      
        #set new_shape_name ""

        # Review if there are any overlapping shapes
        set s_tmp_a [ga [get_shapes [get_objects_by_location -classes shape -intersect $shape_bbox] -filter "layer_name==${layer} && full_name!=$shape_name && net_type==${nettype}"] full_name]
        set s_tmp_b [ga [get_shapes [get_objects_by_location -classes shape -touching $shape_bbox] -filter "layer_name==${layer} && full_name!=$shape_name && net_type==${nettype}"] full_name]
        set s_tmp_c [ga [get_shapes [get_objects_by_location -classes shape -within $shape_bbox] -filter "layer_name==${layer} && full_name!=$shape_name && net_type==${nettype}"] full_name]

        #s_tmp -> overlapping Vnnaon
        set s_tmp [get_shapes "$s_tmp_a $s_tmp_b $s_tmp_c"]
               
foreach_in_collection s_tmp_1 [get_shapes $s_tmp] {
            set shape_intersect [ga [get_shapes $s_tmp_1 -filter "full_name!~*REC*"] full_name]
            set shape_intersect_owner [get_object_name [ga [get_shapes $shape_intersect] owner ]]  
            set other_size [sc [get_shapes $s_tmp_1] ]
   set shape_intersect_bbox [ga [get_shapes $shape_intersect -filter "object_class==shape"] bbox ]
                lassign [mk_get_coords4bbox $shape_bbox ] ax0 ay0 ax1 ay1
                lassign [mk_get_coords4bbox $shape_intersect_bbox ] bx0 by0 bx1 by1
set overlap_bot ""
                set overlap_top ""
set removal_status ""
set overlap_bbox ""
#shape_tmp_1 -> Vss

if {$other_size == 0} {
   set removal_status "No overlaps"
} elseif {$other_size > 0 && $shape_intersect_owner != $shape_owner} {
                incr num_shorts

                set one_side 1
set_fixed_objects [get_shapes $shape_name] -unfix

#If secondary inside shield
if {$ay0 < $by0 && $ay1 > $by1} {
   foreach {overlap_bot overlap_top} {$by0 $by1} {}
}
#If shield inside secondary and other simple overlaps
if {$ay0 > $by0} {
                    set overlap_bot $ay0
                } else {
                    set overlap_bot $by0
                }
                if {$ay1 < $by1} {
                    set overlap_top $ay1
                } else {
                    set overlap_top $by1
                }

                set overlap_bbox "{$ax0 $overlap_bot} {$ax1 $overlap_top}"
split_objects [get_shapes $shape_tmp_1] -rect $overlap_bbox  
gui_change_highlight -add -collection [get_shapes $shape_name] -color yellow
                ## find unique  
                set keep_bot ""
                set keep_top ""
                if {$ay0 <= $by0} {
                    set keep_bot $ay0
                } else {
                    set keep_bot [expr $by1 + $m15_space]
                }
                if {$ay1 < $by1} {
                    set keep_top [expr $by0 - $m15_space]
                } else {
                    set keep_top $ay1
                }

                set keep_bbox "{$ax0 $keep_bot} {$ax1 $keep_top}"
 
##Just to CHECK if the entire secondary is inside the Shield
                if { $by0>$ay0 && $by1 < $ay1} {
                    set one_side 0
   set removal_status "PARTIAL $keep_bbox"
                 
}

                # Decide if partial wire/snip or entire shorts/ remove shape
                ## remove the dont touch
                 
                puts $infile_0 "Shape - $shape_name"
                puts $infile_0 "set_fixed_objects \[get_shapes $shape_name ] -unfix"

#To print the status if entire shield is inside the secondary:
                if {$overlap_bot == $ay0 &&  $overlap_top==$ay1 && $remove==1} {
                    print_info "Removing entire shape $shape_name"
                    puts $infile_0 "remove_shape $shape_name"

  set removal_status "FULL"  
                    break
                } elseif {$remove==1 && $one_side==1} {
                    print_info "Snipping shape $shape_name"    
puts $infile_0 "split_objects -rect $overlap_bbox"

   set removal_status "PARTIAL $keep_bbox"
                    break
                } elseif {$remove==1 && $one_side==0} {
                    ## split_objects on top first
                    # Top region to keep $by1+ $m15_space to $ay1
                    # Bot region to keep $ay0 to $by0 - $m15_space
                    #add extra cases for multiple overlaps
                    print_info "Splitting shape $shape_name"
                    set dx0 $ax0
                    set dx1 $ax1
                    set dy0 [expr $by0 - $m15_space]
                    set dy1 [expr $by1 + $m15_space]
                    set rect "{{$dx0 $dy0} {$dx1 $dy1}}"
                    puts $infile_0 "split_objects -rect $rect  \[get_shapes $shape_name]"
                    puts $infile_0 "remove_shapes \[get_shapes $shape_name]"
                    break
                }

		split_objects -rect $overlap_bbox
           }  
}
		
                        ## FIXME: Assuming that this is M15 RN
                puts $infile " $layer |    $shape_owner    |    $shape_name    |    $shape_intersect_owner    |    $shape_intersect    |    $shape_bbox    |    $shape_intersect_bbox    |    $overlap_bbox | $removal_status  "
                #puts $infile "-"
       

    ### Maybe here do the "final Snipping ?
# split_objects -rect $overlap_bbox
   
}
    print_info "Number of unique shorts $num_shorts"
    print_info "File printed ${area}/${partition}_pwrshort.rpt"
    print_info "Change list printed ${area}/${partition}_pwrshort_rm.tcl "

    close $infile
    close $infile_0
}




proc rm_pwr_shorts {} {

    # first check for complete overlap
    # Snip from top or bottom

}
