------------------------------------------------------------------------------------------------------------------------------------------------------
-- Company: TAMU
-- Engineer: Evaldas Juska (evaldas.juska@cern.ch, evka85@gmail.com)
-- 
-- Create Date:    15:04 2016-05-10
-- Module Name:    GEM System Registers
-- Description:    this module provides registers for GEM system-wide setting  
------------------------------------------------------------------------------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.ipbus.all;
use work.gem_pkg.all;
use work.registers.all;
use work.ttc_pkg.all;
use work.gem_board_config_package.all;

entity gem_system_regs is
port(
    
    reset_i                     : in std_logic;

    ttc_clks_i                  : in t_ttc_clks;

    ipb_clk_i                   : in std_logic;
    ipb_reset_i                 : in std_logic;
    
    ipb_mosi_i                  : in ipb_wbus;
    ipb_miso_o                  : out ipb_rbus;
    
    board_id_o                  : out std_logic_vector(15 downto 0);

    loopback_gbt_test_en_o      : out std_logic;
    use_v3b_elink_mapping_o     : out std_logic;
    use_vfat_addressing_o       : out std_logic;

    vfat3_sc_only_mode_o        : out std_logic;
    manual_link_reset_o         : out std_logic;
    global_reset_o              : out std_logic;
    
    gemloader_stats_i           : in  t_gem_loader_stats
);
end gem_system_regs;

architecture gem_system_regs_arch of gem_system_regs is

    signal reset_cnt                : std_logic := '0';
    
    signal board_id                 : std_logic_vector(15 downto 0) := (others => '0');
    signal gem_station              : integer range 0 to 2;
    signal version_major            : integer range 0 to 255; 
    signal version_minor            : integer range 0 to 255; 
    signal version_build            : integer range 0 to 255;
    signal firmware_date            : std_logic_vector(31 downto 0);
    signal num_of_oh                : std_logic_vector(4 downto 0);
    signal board_type               : std_logic_vector(3 downto 0);
    
    signal loopback_gbt_test_en     : std_logic;
    
    signal vfat3_sc_only_mode       : std_logic;
    
    signal use_v3b_elink_mapping    : std_logic;
    signal use_vfat_addressing      : std_logic;

    signal global_reset_timer       : integer range 0 to 100 := 0;
    signal global_reset_trig        : std_logic;

    --== LEGACY Firmware date and version (taken from GLIB) ==--
    -- TODO: remove legacy firmware date and version once the software is ready 
    constant c_legacy_sys_ver_year :integer range 0 to 99 :=17;
    constant c_legacy_sys_ver_month:integer range 0 to 12 :=05;
    constant c_legacy_sys_ver_day  :integer range 0 to 31 :=23;
    constant c_legacy_board_id     : std_logic_vector(31 downto 0) := x"474c4942"; -- GLIB
    constant c_legacy_sys_id       : std_logic_vector(31 downto 0) := x"32307631"; -- '2_0_v1'
    
    signal legacy_board_id     : std_logic_vector(31 downto 0);
    signal legacy_sys_id       : std_logic_vector(31 downto 0);
    signal legacy_fw_version   : std_logic_vector(31 downto 0);

    ------ Register signals begin (this section is generated by <gem_amc_repo_root>/scripts/generate_registers.py -- do not edit)
    ------ Register signals end ----------------------------------------------
    
begin

    --=== version and date === --
    
    firmware_date <= C_FIRMWARE_DATE;
    version_major <= C_FIRMWARE_MAJOR;
    version_minor <= C_FIRMWARE_MINOR;
    version_build <= C_FIRMWARE_BUILD;
    gem_station <= CFG_GEM_STATION;

    --=== board type and configuration parameters ===--
    board_type     <= CFG_BOARD_TYPE;
    num_of_oh      <= std_logic_vector(to_unsigned(CFG_NUM_OF_OHs, 5));
    
    --=== version and date === --
    -- TODO: remove legacy firmware date and version once the software is ready
    legacy_board_id      <= c_legacy_board_id;
    legacy_sys_id        <= c_legacy_sys_id;
    legacy_fw_version    <= std_logic_vector(to_unsigned(version_major, 4)) &
                            std_logic_vector(to_unsigned(version_minor, 4)) &
                            std_logic_vector(to_unsigned(version_build, 8)) &
                            std_logic_vector(to_unsigned(c_legacy_sys_ver_year, 7)) &
                            std_logic_vector(to_unsigned(c_legacy_sys_ver_month, 4)) &
                            std_logic_vector(to_unsigned(c_legacy_sys_ver_day, 5));
            
    --=== Tests === --
    loopback_gbt_test_en_o <= loopback_gbt_test_en; 
    
    vfat3_sc_only_mode_o <= vfat3_sc_only_mode;
    use_v3b_elink_mapping_o <= use_v3b_elink_mapping;
    use_vfat_addressing_o <= use_vfat_addressing;

    process (ttc_clks_i.clk_40)
    begin
        if rising_edge(ttc_clks_i.clk_40) then
            if (global_reset_trig = '1') then
                global_reset_timer <= 100;
                global_reset_o <= '0';
            else
                -- wait for 50 cycles after the trigger, and then keep the reset on for 50 cycles
                if (global_reset_timer = 0) then
                    global_reset_o <= '0';
                    global_reset_timer <= 0;
                elsif (global_reset_timer > 50) then
                    global_reset_o <= '0';
                    global_reset_timer <= global_reset_timer - 1; 
                else
                    global_reset_o <= '1';
                    global_reset_timer <= global_reset_timer - 1;
                end if;
            end if;
        end if;
    end process;

    --===============================================================================================
    -- this section is generated by <gem_amc_repo_root>/scripts/generate_registers.py (do not edit) 
    --==== Registers begin ==========================================================================

    --==== Registers end ============================================================================

end gem_system_regs_arch;
