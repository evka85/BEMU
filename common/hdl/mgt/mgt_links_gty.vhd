------------------------------------------------------------------------------------------------------------------------------------------------------
-- Company: TAMU
-- Engineer: Evaldas Juska (evaldas.juska@cern.ch, evka85@gmail.com)
-- 
-- Create Date:    2020-06-09
-- Module Name:    MGT_LINKS_GTY 
-- Description:    This is a wrapper of multiple GTY links 
------------------------------------------------------------------------------------------------------------------------------------------------------

-- NOTES:
--   * clocking: can we drive the BUFG_GT with MMCM?
--   * use TX + RX multi-lane buffer bypass auto phase alignment -- this removes the needs for sync fifos on the RX path
--   * figure out the RX termination
--   * try to use QPLL for 4.8 links (?)

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_misc.all;

library unisim;
use unisim.vcomponents.all;

use work.gem_pkg.all;
use work.mgt_pkg.all;
use work.ttc_pkg.all;
use work.ipbus.all;
use work.gem_board_config_package.all;

entity mgt_links_gty is
    generic(
        g_NUM_CHANNELS          : integer;
        g_NUM_QPLLS             : integer;
        g_LINK_CONFIG           : t_mgt_config_arr;
        g_MASTER_CHANNEL        : integer ;
        g_STABLE_CLK_PERIOD     : integer range 4 to 250 := 20  -- Period of the stable clock driving the state machines (ns)        
    );
    port(
        
        reset_i                 : in  std_logic;
        clk_stable_i            : in  std_logic;
        
        ttc_clks_i              : in  t_ttc_clks;
        ttc_clks_locked_i       : in  std_logic;
        ttc_clks_reset_o        : out std_logic;
        
        channel_refclk_arr_i    : in  t_mgt_refclks_arr(g_NUM_CHANNELS-1 downto 0);
        
        status_arr_o            : out t_mgt_status_arr(g_NUM_CHANNELS-1 downto 0);
        ctrl_arr_i              : in  t_mgt_ctrl_arr(g_NUM_CHANNELS-1 downto 0);
        
        tx_data_arr_i           : in  t_mgt_64b_tx_data_arr(g_NUM_CHANNELS-1 downto 0);
        rx_data_arr_o           : out t_mgt_64b_rx_data_arr(g_NUM_CHANNELS-1 downto 0);
        
        tx_usrclk_arr_o         : out std_logic_vector(g_NUM_CHANNELS-1 downto 0);
        rx_usrclk_arr_o         : out std_logic_vector(g_NUM_CHANNELS-1 downto 0);

        master_txoutclk_o       : out std_logic;
        master_txusrclk_o       : out std_logic;
        master_rxusrclk_o       : out std_logic;
        
        ipb_reset_i             : in  std_logic;
        ipb_clk_i               : in  std_logic;
        ipb_mosi_i              : in  ipb_wbus;
        ipb_miso_o              : out ipb_rbus
        
    );
end mgt_links_gty;

architecture mgt_links_gty_arch of mgt_links_gty is

    signal chan_clks_in_arr     : t_mgt_clk_in_arr(g_NUM_CHANNELS-1 downto 0);
    signal chan_clks_out_arr    : t_mgt_clk_out_arr(g_NUM_CHANNELS-1 downto 0);

    signal tx_data_arr          : t_mgt_64b_tx_data_arr(g_NUM_CHANNELS-1 downto 0);
    signal rx_data_arr          : t_mgt_64b_rx_data_arr(g_NUM_CHANNELS-1 downto 0);

    signal tx_cpll_reset_arr    : std_logic_vector(g_NUM_CHANNELS-1 downto 0);
    signal rx_cpll_reset_arr    : std_logic_vector(g_NUM_CHANNELS-1 downto 0);
    signal cpll_status_arr      : t_mgt_cpll_status_arr(g_NUM_CHANNELS-1 downto 0);

    signal chan_drp_in_arr      : t_drp_in_arr(g_NUM_CHANNELS-1 downto 0) := (others => DRP_IN_NULL);
    signal chan_drp_out_arr     : t_drp_out_arr(g_NUM_CHANNELS-1 downto 0);

    signal tx_slow_ctrl_arr     : t_mgt_tx_slow_ctrl_arr(g_NUM_CHANNELS-1 downto 0);
    signal rx_slow_ctrl_arr     : t_mgt_rx_slow_ctrl_arr(g_NUM_CHANNELS-1 downto 0);
    signal rx_fast_ctrl_arr     : t_mgt_rx_fast_ctrl_arr(g_NUM_CHANNELS-1 downto 0);
    signal tx_init_arr          : t_mgt_tx_init_arr(g_NUM_CHANNELS-1 downto 0);
    signal rx_init_arr          : t_mgt_rx_init_arr(g_NUM_CHANNELS-1 downto 0);
    signal misc_ctrl_arr        : t_mgt_misc_ctrl_arr(g_NUM_CHANNELS-1 downto 0);

    signal sc_tx_reset_arr      : std_logic_vector(g_NUM_CHANNELS-1 downto 0);
    signal sc_rx_reset_arr      : std_logic_vector(g_NUM_CHANNELS-1 downto 0);

    signal tx_status_arr        : t_mgt_tx_status_arr(g_NUM_CHANNELS-1 downto 0);
    signal rx_status_arr        : t_mgt_rx_status_arr(g_NUM_CHANNELS-1 downto 0);
    signal misc_status_arr      : t_mgt_misc_status_arr(g_NUM_CHANNELS-1 downto 0);
    
    signal tx_reset_done_arr    : std_logic_vector(g_NUM_CHANNELS-1 downto 0);
    signal rx_reset_done_arr    : std_logic_vector(g_NUM_CHANNELS-1 downto 0);
    signal tx_phalign_done_arr  : std_logic_vector(g_NUM_CHANNELS-1 downto 0);
    signal rx_phalign_done_arr  : std_logic_vector(g_NUM_CHANNELS-1 downto 0);
    
    -- multi-lane tx phase alignment signals
    signal txph_syncallin_arr   : std_logic_vector(g_NUM_CHANNELS-1 downto 0) := (others => '0');
    signal txph_syncin_arr      : std_logic_vector(g_NUM_CHANNELS-1 downto 0) := (others => '0');
    signal txph_syncmode_arr    : std_logic_vector(g_NUM_CHANNELS-1 downto 0) := (others => '0');
    signal txph_dlysreset_arr   : std_logic_vector(g_NUM_CHANNELS-1 downto 0) := (others => '0');
    signal txph_phaligndone_arr : std_logic_vector(g_NUM_CHANNELS-1 downto 0) := (others => '1');
    signal txph_syncdone_arr    : std_logic_vector(g_NUM_CHANNELS-1 downto 0) := (others => '0');
    signal txph_syncout_arr     : std_logic_vector(g_NUM_CHANNELS-1 downto 0) := (others => '0');
    
begin

    tx_data_arr <= tx_data_arr_i;
    rx_data_arr_o <= rx_data_arr;
    
    g_channels : for chan in 0 to g_NUM_CHANNELS - 1 generate

        --================================--
        -- Common things for all MGT types
        --================================--
        
        chan_clks_in_arr(chan).refclks <= channel_refclk_arr_i(chan);

        tx_usrclk_arr_o(chan) <= chan_clks_in_arr(chan).txusrclk2;
        rx_usrclk_arr_o(chan) <= chan_clks_in_arr(chan).rxusrclk2;
        
        g_master_clks : if chan = g_MASTER_CHANNEL generate
            master_txoutclk_o <= chan_clks_out_arr(chan).txoutclk;
            master_txusrclk_o <= chan_clks_in_arr(chan).txusrclk2;
            master_rxusrclk_o <= chan_clks_in_arr(chan).rxusrclk2;
        end generate;
        
        status_arr_o(chan).tx_reset_done <= tx_reset_done_arr(chan);
        status_arr_o(chan).rx_reset_done <= rx_reset_done_arr(chan);
        status_arr_o(chan).tx_cpll_locked <= cpll_status_arr(chan).cplllock;
        status_arr_o(chan).rx_cpll_locked <= cpll_status_arr(chan).cplllock;
        status_arr_o(chan).qpll_locked <= '0';

        --===================================================--
        -- TX multi-lane phase alignment signal assignments
        --===================================================--
        
        g_tx_multilane_phalign : if g_LINK_CONFIG(chan).tx_multilane_phalign generate
            tx_init_arr(chan).txsyncallin <= txph_syncallin_arr(chan);
            tx_init_arr(chan).txsyncin <= txph_syncin_arr(chan);      
            tx_init_arr(chan).txsyncmode <= txph_syncmode_arr(chan);    
            tx_init_arr(chan).txdlysreset <= txph_dlysreset_arr(chan);   
            txph_phaligndone_arr(chan) <= tx_status_arr(chan).txphaligndone; 
            txph_syncdone_arr(chan) <= tx_status_arr(chan).txsyncdone;
            txph_syncout_arr(chan) <= tx_status_arr(chan).txsyncout;
        end generate;
        
        --================================--
        -- GBTX MGT type
        --================================--
        g_chan_gbtx : if g_LINK_CONFIG(chan).link_type = MGT_GBTX generate
        
            -- TX user clocks
            chan_clks_in_arr(chan).txusrclk <= ttc_clks_i.clk_120;
            chan_clks_in_arr(chan).txusrclk2 <= ttc_clks_i.clk_120;
            
            -- RX user clocks when using elastic buffer
            g_rx_use_buf : if g_LINK_CONFIG(chan).rx_use_buf generate
                chan_clks_in_arr(chan).rxusrclk <= ttc_clks_i.clk_120;
                chan_clks_in_arr(chan).rxusrclk2 <= ttc_clks_i.clk_120;
            end generate;
            
            -- RX user clocks when elastic buffer is bypassed
            g_rx_no_buf : if not g_LINK_CONFIG(chan).rx_use_buf generate
                
                i_rxoutclk_buf : BUFG_GT
                    port map(
                        O       => chan_clks_in_arr(chan).rxusrclk,
                        CE      => '1',
                        CEMASK  => '0',
                        CLR     => '0',
                        CLRMASK => '0',
                        DIV     => "000",
                        I       => chan_clks_out_arr(chan).rxoutclk
                    );                

                chan_clks_in_arr(chan).rxusrclk2 <= chan_clks_in_arr(chan).rxusrclk;
            end generate;

            -- generic control signals
            rx_fast_ctrl_arr(chan).rxslide <= ctrl_arr_i(chan).rxslide;
            
            i_chan_gbtx : entity work.gty_channel_gbtx
                generic map(
                    g_REFCLK_01   => g_LINK_CONFIG(chan).use_refclk_01,
                    g_QPLL_01     => g_LINK_CONFIG(chan).use_qpll_01,
                    g_USE_QPLL    => g_LINK_CONFIG(chan).use_qpll
                )
                port map(
                    clk_stable_i   => clk_stable_i,
                    clks_i         => chan_clks_in_arr(chan),
                    clks_o         => chan_clks_out_arr(chan),
                    cpllreset_i    => tx_cpll_reset_arr(chan),
                    cpll_status_o  => cpll_status_arr(chan),
                    drp_i          => chan_drp_in_arr(chan),
                    drp_o          => chan_drp_out_arr(chan),
                    tx_slow_ctrl_i => tx_slow_ctrl_arr(chan),
                    tx_init_i      => tx_init_arr(chan),
                    tx_status_o    => tx_status_arr(chan),
                    rx_slow_ctrl_i => rx_slow_ctrl_arr(chan),
                    rx_fast_ctrl_i => rx_fast_ctrl_arr(chan),
                    rx_init_i      => rx_init_arr(chan),
                    rx_status_o    => rx_status_arr(chan),
                    misc_ctrl_i    => misc_ctrl_arr(chan),
                    misc_status_o  => misc_status_arr(chan),
                    tx_data_i      => tx_data_arr(chan),
                    rx_data_o      => rx_data_arr(chan)
                );
        
        end generate;

        --================================--
        -- LpGBT MGT type
        --================================--
        g_chan_lpgbt : if g_LINK_CONFIG(chan).link_type = MGT_LPGBT generate
        
            -- TX user clocks
            chan_clks_in_arr(chan).txusrclk <= ttc_clks_i.clk_320;
            chan_clks_in_arr(chan).txusrclk2 <= ttc_clks_i.clk_320;
            
            -- RX user clocks when using elastic buffer
            g_rx_use_buf : if g_LINK_CONFIG(chan).rx_use_buf generate
                chan_clks_in_arr(chan).rxusrclk <= ttc_clks_i.clk_320;
                chan_clks_in_arr(chan).rxusrclk2 <= ttc_clks_i.clk_320;
            end generate;
            
            -- RX user clocks when elastic buffer is bypassed
            g_rx_no_buf : if not g_LINK_CONFIG(chan).rx_use_buf generate
                
                i_rxoutclk_buf : BUFG_GT
                    port map(
                        O       => chan_clks_in_arr(chan).rxusrclk,
                        CE      => '1',
                        CEMASK  => '0',
                        CLR     => '0',
                        CLRMASK => '0',
                        DIV     => "000",
                        I       => chan_clks_out_arr(chan).rxoutclk
                    );                

                chan_clks_in_arr(chan).rxusrclk2 <= chan_clks_in_arr(chan).rxusrclk;
            end generate;

            -- generic control signals
            rx_fast_ctrl_arr(chan).rxslide <= ctrl_arr_i(chan).rxslide;
            
            i_chan_lpgbt : entity work.gty_channel_lpgbt
                generic map(
                    g_REFCLK_01   => g_LINK_CONFIG(chan).use_refclk_01,
                    g_QPLL_01     => g_LINK_CONFIG(chan).use_qpll_01,
                    g_USE_QPLL    => g_LINK_CONFIG(chan).use_qpll
                )
                port map(
                    clk_stable_i   => clk_stable_i,
                    clks_i         => chan_clks_in_arr(chan),
                    clks_o         => chan_clks_out_arr(chan),
                    cpllreset_i    => tx_cpll_reset_arr(chan),
                    cpll_status_o  => cpll_status_arr(chan),
                    drp_i          => chan_drp_in_arr(chan),
                    drp_o          => chan_drp_out_arr(chan),
                    tx_slow_ctrl_i => tx_slow_ctrl_arr(chan),
                    tx_init_i      => tx_init_arr(chan),
                    tx_status_o    => tx_status_arr(chan),
                    rx_slow_ctrl_i => rx_slow_ctrl_arr(chan),
                    rx_fast_ctrl_i => rx_fast_ctrl_arr(chan),
                    rx_init_i      => rx_init_arr(chan),
                    rx_status_o    => rx_status_arr(chan),
                    misc_ctrl_i    => misc_ctrl_arr(chan),
                    misc_status_o  => misc_status_arr(chan),
                    tx_data_i      => tx_data_arr(chan),
                    rx_data_o      => rx_data_arr(chan)
                );
        
        end generate;

        --================================--
        -- TX Reset FSM
        --================================--
        
        i_tx_reset : entity work.gty_channel_reset
            generic map(
                g_STABLE_CLK_PERIOD => g_STABLE_CLK_PERIOD,
                g_USRCLK_WAIT_TIME  => 10_000,
                g_CPLL_USED         => not g_LINK_CONFIG(chan).use_qpll,
                g_QPLL0_USED        => g_LINK_CONFIG(chan).use_qpll and (g_LINK_CONFIG(chan).use_qpll_01 = 0),
                g_QPLL1_USED        => g_LINK_CONFIG(chan).use_qpll and (g_LINK_CONFIG(chan).use_qpll_01 = 1)
            )
            port map(
                reset_i           => reset_i or ctrl_arr_i(chan).txreset or sc_tx_reset_arr(chan),
                clk_stable_i      => clk_stable_i,
                power_good_i      => misc_status_arr(chan).powergood,
                check_usrclk_i    => tx_status_arr(chan).txpmaresetdone,
                txrxresetdone_i   => tx_status_arr(chan).txresetdone,               
                usrclk_locked_i   => ttc_clks_locked_i,
                cpll_locked_i     => cpll_status_arr(chan).cplllock,
                qpll0_locked_i    => '0',
                qpll1_locked_i    => '0',
                gtreset_o         => tx_init_arr(chan).gttxreset,
                usrclkrdy_o       => tx_init_arr(chan).txuserrdy,
                cpllreset_o       => tx_cpll_reset_arr(chan),
                qpll0_reset_o     => open,
                qpll1_reset_o     => open,
                reset_done_o      => tx_reset_done_arr(chan)
            );
        
        --================================--
        -- RX Reset FSM
        --================================--
        
        i_rx_reset : entity work.gty_channel_reset
            generic map(
                g_STABLE_CLK_PERIOD => g_STABLE_CLK_PERIOD,
                g_USRCLK_WAIT_TIME  => 500_000, -- give ample of time for the CDR to lock
                g_CPLL_USED         => not g_LINK_CONFIG(chan).use_qpll,
                g_QPLL0_USED        => g_LINK_CONFIG(chan).use_qpll and (g_LINK_CONFIG(chan).use_qpll_01 = 0),
                g_QPLL1_USED        => g_LINK_CONFIG(chan).use_qpll and (g_LINK_CONFIG(chan).use_qpll_01 = 1)
            )
            port map(
                reset_i           => reset_i or ctrl_arr_i(chan).rxreset or sc_rx_reset_arr(chan),
                clk_stable_i      => clk_stable_i,
                power_good_i      => misc_status_arr(chan).powergood,
                check_usrclk_i    => rx_status_arr(chan).rxpmaresetdone,
                txrxresetdone_i   => rx_status_arr(chan).rxresetdone,               
                usrclk_locked_i   => ttc_clks_locked_i,
                cpll_locked_i     => cpll_status_arr(chan).cplllock,
                qpll0_locked_i    => '0',
                qpll1_locked_i    => '0',
                gtreset_o         => rx_init_arr(chan).gtrxreset,
                usrclkrdy_o       => rx_init_arr(chan).rxuserrdy,
                cpllreset_o       => rx_cpll_reset_arr(chan),
                qpll0_reset_o     => open,
                qpll1_reset_o     => open,
                reset_done_o      => rx_reset_done_arr(chan)
            );
        
        --=========================================--
        -- RX Phase Alignment (single-lane auto)
        --=========================================--

        i_rx_phalign : entity work.mgt_phalign_single_auto
            generic map(
                g_STABLE_CLK_PERIOD => g_STABLE_CLK_PERIOD
            )
            port map(
                clk_stable_i         => clk_stable_i,
                channel_reset_done_i => rx_reset_done_arr(chan),
                mgt_syncallin_o      => rx_init_arr(chan).rxsyncallin,
                mgt_syncin_o         => rx_init_arr(chan).rxsyncin,
                mgt_syncmode_o       => rx_init_arr(chan).rxsyncmode,
                mgt_dlysreset_o      => rx_init_arr(chan).rxdlysreset,
                mgt_phaligndone_i    => rx_status_arr(chan).rxphaligndone,
                mgt_syncdone_i       => rx_status_arr(chan).rxsyncdone,
                phase_align_done_o   => rx_phalign_done_arr(chan)
            );
           
    end generate;

    --=========================================--
    -- TX Phase Alignment (multi-lane auto)
    --=========================================--

    i_tx_phalign : entity work.mgt_phalign_multi_auto
        generic map(
            g_STABLE_CLK_PERIOD  => g_STABLE_CLK_PERIOD,
            g_NUM_CHANNELS       => g_NUM_CHANNELS,
            g_MASTER_CHANNEL     => g_MASTER_CHANNEL
        )
        port map(
            clk_stable_i             => clk_stable_i,
            channel_reset_done_arr_i => tx_reset_done_arr,
            mgt_syncallin_arr_o      => txph_syncallin_arr,
            mgt_syncin_arr_o         => txph_syncin_arr,
            mgt_syncmode_arr_o       => txph_syncmode_arr,
            mgt_dlysreset_arr_o      => txph_dlysreset_arr,
            mgt_phaligndone_arr_i    => txph_phaligndone_arr,
            mgt_syncdone_arr_i       => txph_syncdone_arr,
            mgt_syncout_arr_i        => txph_syncout_arr,
            phase_align_done_arr_o   => tx_phalign_done_arr
        );

    --=========================================--
    -- Slow control
    --=========================================--

    i_slow_control : entity work.mgt_slow_control
        generic map(
            g_NUM_CHANNELS => g_NUM_CHANNELS
        )
        port map(
            clk_stable_i          => clk_stable_i,
            mgt_clks_arr_i        => chan_clks_in_arr,
            tx_reset_arr_o        => sc_tx_reset_arr,
            rx_reset_arr_o        => sc_rx_reset_arr,
            tx_slow_ctrl_arr_o    => tx_slow_ctrl_arr,
            rx_slow_ctrl_arr_o    => rx_slow_ctrl_arr,
            misc_ctrl_arr_o       => misc_ctrl_arr,
            tx_status_arr_i       => tx_status_arr,
            rx_status_arr_i       => rx_status_arr,
            misc_status_arr_i     => misc_status_arr,
            tx_reset_done_arr_i   => tx_reset_done_arr,
            rx_reset_done_arr_i   => rx_reset_done_arr,
            tx_phalign_done_arr_i => tx_phalign_done_arr,
            rx_phalign_done_arr_i => rx_phalign_done_arr,
            cpll_status_arr_i     => cpll_status_arr,
            ipb_clk_i             => ipb_clk_i,
            ipb_reset_i           => ipb_reset_i,
            ipb_mosi_i            => ipb_mosi_i,
            ipb_miso_o            => ipb_miso_o
        );

end mgt_links_gty_arch;
