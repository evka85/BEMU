create_pblock pcie
add_cells_to_pblock [get_pblocks pcie] [get_cells -quiet [list {i_pcie*}]]
resize_pblock [get_pblocks pcie] -add {CLOCKREGION_X3Y4:CLOCKREGION_X7Y7}

create_pblock gem
add_cells_to_pblock [get_pblocks gem] [get_cells -quiet [list {i_gem*}]]
resize_pblock [get_pblocks gem] -add {CLOCKREGION_X3Y8:CLOCKREGION_X7Y11}
