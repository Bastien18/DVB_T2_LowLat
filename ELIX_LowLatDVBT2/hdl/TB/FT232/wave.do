onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /ft232h_sync245_if_tb/ft_clk
add wave -noupdate /ft232h_sync245_if_tb/reset_n
add wave -noupdate /ft232h_sync245_if_tb/ft_data
add wave -noupdate /ft232h_sync245_if_tb/ft_oe_n
add wave -noupdate /ft232h_sync245_if_tb/ft_txe_n
add wave -noupdate /ft232h_sync245_if_tb/ft_wr_n
add wave -noupdate /ft232h_sync245_if_tb/tx_data
add wave -noupdate /ft232h_sync245_if_tb/tx_valid
add wave -noupdate /ft232h_sync245_if_tb/tx_ready
add wave -noupdate /ft232h_sync245_if_tb/dut_inst/txe_n_reg
add wave -noupdate /ft232h_sync245_if_tb/ft_rxf_n
add wave -noupdate /ft232h_sync245_if_tb/ft_rd_n
add wave -noupdate /ft232h_sync245_if_tb/ft_siwu_n
add wave -noupdate /ft232h_sync245_if_tb/rx_data
add wave -noupdate /ft232h_sync245_if_tb/rx_valid
add wave -noupdate /ft232h_sync245_if_tb/rx_ready
add wave -noupdate /ft232h_sync245_if_tb/ft_rx_index
add wave -noupdate /ft232h_sync245_if_tb/ft_data_ft
add wave -noupdate /ft232h_sync245_if_tb/rd_n_prev_model
add wave -noupdate /ft232h_sync245_if_tb/wr_n_prev_model
add wave -noupdate /ft232h_sync245_if_tb/oe_n_prev_check
add wave -noupdate /ft232h_sync245_if_tb/rd_n_prev_check
add wave -noupdate /ft232h_sync245_if_tb/tx_capture
add wave -noupdate /ft232h_sync245_if_tb/tx_capture_idx
add wave -noupdate /ft232h_sync245_if_tb/CLK_PERIOD
add wave -noupdate /ft232h_sync245_if_tb/FT_RX_PAYLOAD
add wave -noupdate /ft232h_sync245_if_tb/MAX_TX_BYTES
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {479500 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 267
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ps
update
WaveRestoreZoom {476349 ps} {756521 ps}
