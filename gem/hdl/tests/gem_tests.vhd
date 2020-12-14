------------------------------------------------------------------------------------------------------------------------------------------------------
-- Company: TAMU
-- Engineer: Evaldas Juska (evaldas.juska@cern.ch, evka85@gmail.com)
-- 
-- Create Date:    20:38:00 2016-08-30
-- Module Name:    GEM_TESTS
-- Description:    This module is the entry point for hardware tests e.g. fiber loopback testing with generated data 
------------------------------------------------------------------------------------------------------------------------------------------------------


library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.gem_pkg.all;
use work.ttc_pkg.all;
use work.ipbus.all;
use work.registers.all;

entity gem_tests is
    generic(
        g_NUM_OF_OHs        : integer;
        g_NUM_GBTS_PER_OH   : integer;
        g_GEM_STATION       : integer
    );
    port(
        -- reset
        reset_i                     : in  std_logic;
        
        -- TTC
        ttc_clk_i                   : in  t_ttc_clks;        
        ttc_cmds_i                  : in  t_ttc_cmds;
        
        -- Test control
        loopback_gbt_test_en_i      : in std_logic;
        
        -- GBT links
        gbt_link_ready_i            : in  std_logic_vector(g_NUM_OF_OHs * g_NUM_GBTS_PER_OH - 1 downto 0);
        gbt_tx_data_arr_o           : out t_gbt_frame_array(g_NUM_OF_OHs * g_NUM_GBTS_PER_OH - 1 downto 0);
        gbt_wide_rx_data_arr_i      : in  t_gbt_wide_frame_array(g_NUM_OF_OHs * g_NUM_GBTS_PER_OH - 1 downto 0);
        
        -- VFAT3 daq input for channel monitoring
        vfat3_daq_links_arr_i       : in t_oh_vfat_daq_link_arr(g_NUM_OF_OHs - 1 downto 0);
        
        -- IPbus
        ipb_reset_i                 : in  std_logic;
        ipb_clk_i                   : in  std_logic;
        ipb_miso_o                  : out ipb_rbus;
        ipb_mosi_i                  : in  ipb_wbus        
    );
end gem_tests;

architecture Behavioral of gem_tests is

    -- reset
    signal reset_global                 : std_logic;
    signal reset_local                  : std_logic;
    signal reset                        : std_logic;

    -- control
    signal gbt_loop_reset               : std_logic;
    signal gbt_loop_oh_select           : std_logic_vector(3 downto 0);
    signal gbt_loop_err_inject          : std_logic;

    -- gbt loopback oh links
    signal gbt_loop_oh_tx_links_arr     : t_gbt_frame_array(g_NUM_GBTS_PER_OH - 1 downto 0);
    signal gbt_loop_oh_rx_links_arr     : t_gbt_wide_frame_array(g_NUM_GBTS_PER_OH - 1 downto 0);
    
    -- gbt loopback status
    signal gbt_loop_locked_arr          : std_logic_vector(g_NUM_GBTS_PER_OH * 14 - 1 downto 0);
    signal gbt_loop_mega_word_cnt_arr   : t_std32_array(g_NUM_GBTS_PER_OH * 14 - 1 downto 0);
    signal gbt_loop_error_cnt_arr       : t_std32_array(g_NUM_GBTS_PER_OH * 14 - 1 downto 0);
    
    -- VFAT3 DAQ monitor
    signal vfat_daq_links24             : t_vfat_daq_link_arr(23 downto 0);
    signal vfat_daqmon_reset            : std_logic;
    signal vfat_daqmon_enable           : std_logic;
    signal vfat_daqmon_oh_select        : std_logic_vector(3 downto 0);
    signal vfat_daqmon_chan_select      : std_logic_vector(6 downto 0);
    signal vfat_daqmon_chan_global_or   : std_logic;
    signal vfat_daqmon_good_evt_cnt_arr : t_std16_array(23 downto 0); 
    signal vfat_daqmon_chan_fire_cnt_arr: t_std16_array(23 downto 0); 
    
    ------ Register signals begin (this section is generated by <gem_amc_repo_root>/scripts/generate_registers.py -- do not edit)
    ------ Register signals end ----------------------------------------------    

begin

    --== Resets ==--
    
    i_reset_sync : entity work.synch
        generic map(
            N_STAGES => 3
        )
        port map(
            async_i => reset_i,
            clk_i   => ttc_clk_i.clk_40,
            sync_o  => reset_global
        );

    reset <= reset_global or reset_local;
    
    --== GBT loopback test ==--
    
    g_use_gbtx : if (g_GEM_STATION = 1) or (g_GEM_STATION = 2) generate
        
        -- instantiate the OH tester
        i_oh_prbs_test : entity work.gbt_prbs_loopback_test
            generic map(
                g_NUM_GBTS_PER_OH => g_NUM_GBTS_PER_OH,
                g_TX_ELINKS_PER_GBT  => 10,
                g_RX_ELINKS_PER_GBT  => 14
            )
            port map(
                reset_i                 => reset or gbt_loop_reset,
                gbt_clk_i               => ttc_clk_i.clk_40,
                gbt_tx_data_arr_o       => gbt_loop_oh_tx_links_arr,
                gbt_wide_rx_data_arr_i  => gbt_loop_oh_rx_links_arr,
                error_inject_en_i       => gbt_loop_err_inject,
                elink_prbs_locked_arr_o => gbt_loop_locked_arr,
                elink_mwords_cnt_arr_o  => gbt_loop_mega_word_cnt_arr,
                elink_error_cnt_arr_o   => gbt_loop_error_cnt_arr
            );
        
        -- fanout the tester TX to all OHs
        g_tx_ohs : for oh in 0 to g_NUM_OF_OHs - 1 generate
            g_tx_gbt : for gbt in 0 to g_NUM_GBTS_PER_OH - 1 generate
                gbt_tx_data_arr_o(oh * g_NUM_GBTS_PER_OH + gbt) <= gbt_loop_oh_tx_links_arr(gbt);
            end generate;
        end generate;
        
        -- MUX the gbt RX links, and route the selected OH to the tester
        g_rx_gbt : for gbt in 0 to g_NUM_GBTS_PER_OH - 1 generate
            gbt_loop_oh_rx_links_arr(gbt) <= gbt_wide_rx_data_arr_i(to_integer(unsigned(gbt_loop_oh_select)) * g_NUM_GBTS_PER_OH + gbt);
        end generate;
        
    end generate;

    --== VFAT3 DAQ monitor ==--
    
    vfat_daq_links24 <= vfat3_daq_links_arr_i(to_integer(unsigned(vfat_daqmon_oh_select)));
    
    g_vfat3_daq_monitors : for i in 0 to 23 generate
        
        i_vfat3_daq_monitor : entity work.vfat3_daq_monitor
            port map(
                reset_i           => reset or vfat_daqmon_reset,
                enable_i          => vfat_daqmon_enable,
                ttc_clk_i         => ttc_clk_i,
                data_en_i         => vfat_daq_links24(i).data_en,
                data_i            => vfat_daq_links24(i).data,
                event_done_i      => vfat_daq_links24(i).event_done,
                crc_error_i       => vfat_daq_links24(i).crc_error,
                chan_global_or_i  => vfat_daqmon_chan_global_or,
                chan_single_idx_i => vfat_daqmon_chan_select,
                cnt_good_events_o => vfat_daqmon_good_evt_cnt_arr(i),
                cnt_chan_fired_o  => vfat_daqmon_chan_fire_cnt_arr(i)
            );
        
    end generate; 
    
    --===============================================================================================
    -- this section is generated by <gem_amc_repo_root>/scripts/generate_registers.py (do not edit) 
    --==== Registers begin ==========================================================================

    --==== Registers end ============================================================================

end Behavioral;