--------------------------------------------------------------------------------
-- Title       : ft232_bridge_tb
-- Project     : ELIX_LowLat_DVBT2
--------------------------------------------------------------------------------
-- File        : ft232_bridge_tb.vhd
-- Author      : Bastien Pillonel <bastien.pillonel@heig-vd.ch>
-- Company     : HEIG-VD
-- Created     : Thu Feb  13 10:51:46 2026
-- Last update : Thu Feb  13 10:54:56 2026
-- Platform    : Default Part Number
-- Standard    : <VHDL-2008>
--------------------------------------------------------------------------------
-- Copyright (c) 2026 HEIG-VD
-------------------------------------------------------------------------------
-- Description: 
--------------------------------------------------------------------------------
-- Revisions:  Revisions and documentation are controlled by
-- the revision control system (RCS).  The RCS should be consulted
-- on revision history.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all

entity tb_ft232_dut is
end entity;

architecture tb of tb_ft232_dut is
  -----------------------------------------------------------------------------
  -- Clocks / resets
  -----------------------------------------------------------------------------
  signal ft_clk   : std_logic := '0';
  signal nios_clk : std_logic := '0';
  signal reset_n  : std_logic := '0';

  -- 60MHz
  constant FT_CLOCK_PERIOD : time := 16.666ns;
  -- 80MHz
  constant NIOS_CLK_PERIOD : time := 12.5ns;

  -----------------------------------------------------------------------------
  -- FTDI pin-level interface to ft232_interface
  -----------------------------------------------------------------------------
  signal ft_data : std_logic_vector(7 downto 0);
  signal rxf_n   : std_logic := '1';
  signal txe_n   : std_logic := '1';
  signal rd_n    : std_logic;
  signal wr_n    : std_logic;
  signal oe_n    : std_logic;

  -----------------------------------------------------------------------------
  -- Stream between ft232_interface and bridge dispatcher
  -----------------------------------------------------------------------------
  signal s_rx_data  : std_logic_vector(7 downto 0);
  signal s_rx_valid : std_logic;
  signal s_rx_ready : std_logic;

  signal s_tx_data  : std_logic_vector(7 downto 0);
  signal s_tx_valid : std_logic;
  signal s_tx_ready : std_logic;

  -----------------------------------------------------------------------------
  -- DVB-T2 FIFO interface (sink)
  -----------------------------------------------------------------------------
  signal dvbt2_rx_data  : std_logic_vector(7 downto 0);
  signal dvbt2_rx_valid : std_logic;
  signal dvbt2_rx_ready : std_logic := '1';

  -- Unused TX FGPA->USB DVB-T2 interface keep tied safe
  signal dvbt2_tx_data  : std_logic_vector(7 downto 0) := (others => '0');
  signal dvbt2_tx_valid : std_logic                    := '0';
  signal dvbt2_tx_ready : std_logic;

  -----------------------------------------------------------------------------
  -- Avalon-MM signals to bridge dispatcher (word addressed)
  -----------------------------------------------------------------------------
  signal avs_address     : std_logic_vector(3 downto 0)  := (others => '0');
  signal avs_read        : std_logic                     := '0';
  signal avs_write       : std_logic                     := '0';
  signal avs_writedata   : std_logic_vector(31 downto 0) := (others => '0');
  signal avs_readdata    : std_logic_vector(31 downto 0);
  signal avs_waitrequest : std_logic;

  -----------------------------------------------------------------------------
  -- FTDI behavioral model FIFOs (host->FPGA and FPGA->host)
  -----------------------------------------------------------------------------
  type byte_array_t is array (natural range <>) of std_logic_vector(7 downto 0);

  constant FTDI_FIFO_DEPTH : 4096;

  type fifo_t is record
    mem  : byte_array_t(0 to FTDI_FIFO_DEPTH - 1);
    wrp  : integer range 0 to FTDI_FIFO_DEPTH - 1;
    rdp  : integer range 0 to FTDI_FIFO_DEPTH - 1;
    used : integer range 0 to FTDI_FIFO_DEPTH;
  end record;

  signal h2f : fifo_t := (mem => (others => (others => '0')), wrp => 0, rdp => 0, used => 0);
  signal f2h : fifo_t := (mem => (others => (others => '0')), wrp => 0, rdp => 0, used => 0);

  signal ftdi_drive_data : std_logic_vector(7 downto 0) := (others => '0');

  -----------------------------------------------------------------------------
  -- Helpers: pack/unpack for NIOS_PKT_16x64 style packets
  -----------------------------------------------------------------------------
  function to_u64_le(bytes : byte_array_t) return unsigned is
    variable v               : unsigned(63 downto 0) := (others => '0');
  begin
    for i in 0 to 7 loop
      v := v or (unsigned(bytes(i)) sll (8 * i));
    end loop;
    return v;
  end function;

  procedure fifo_push (signal f : inout fifo_t; b : std_logic_vector(7 downto 0)) is
  begin
    assert f.used < FTDI_FIFO_DEPTH report "FIFO overflow" severity failure;
    f.mem(f.wrp) <= b;
    f.wrp        <= (f.wrp + 1) mod FTDI_FIFO_DEPTH;
    f.used       <= f.used + 1;
  end procedure;

  procedure fifo_pop (signal f : inout fifo_t; variable b : out std_logic_vector(7 downto 0)) is
  begin
    assert f.used > 0 report "FIFO underflow" severity failure;
    b      <= f.mem(f.rdp);
    f.rdp  <= (f.rdp + 1) mod FTDI_FIFO_DEPTH;
    f.used <= f.used - 1;
  end procedure;

  -----------------------------------------------------------------------------
  -- CTRL test vector table
  -- Each vector is: 16B request + 16B response expected at host side.
  -----------------------------------------------------------------------------
  type pkt16_t is array (0 to 15) of std_logic_vector(7 downto 0);
  type vec_t is record
    name : string(1 to 24);
    req  : pkt16_t;
    resp : pkt16_t;
  end record;

  -- NIOS_PKT_16x64 fields reminder:
  -- [0]='E', [1]=target, [2]=flags (bit0 write, bit1 success in resp), [3]=0
  -- [4..5]=addr LE16, [6..13]=data LE64, [14..15]=0
  --
  -- RFIC target = 0x01, addr = (chan<<8)|cmd
  -- chan: 0x00 RX, 0x01 TX, 0x0F system
  constant MAGIC_E : std_logic_vector(7 downto 0) := x"45";

  -- Example response template echo request but set SUCCESS in flags byte2
  function mk_success_resp(req : pkt16_t) return pkt16_t is
    variable r                   : pkt16_t := req;
  begin
    r(2) := std_logic_vector(unsigned(req(2)) or to_unsigned(2, 8));
    return r;
  end function;

  -- Helper to build a RFIC read request
  function mk_rfic_read (cmd : natural; chan : natural) return pkt16_t is
    variable p    : pkt16_t := (others => (others => '0'));
    variable addr : unsigned(15 downto 0);
  begin
    p(0) := MAGIC_E;
    p(1) := x"01"; -- RFIC target
    p(2) := x"00"; -- read
    p(3) := x"00";
    addr := (to_unsigned(chan, 8) sll 8) or to_unsigned(cmd, 8);
    p(4) := std_logic_vector(addr(7 downto 0));
    p(5) := std_logic_vector(addr(15 downto 8));
    return p;
  end function;

  -- Helper to build a RFIC write request with 64b value
  function mk_rfic_write (cmd : natural; chan : natural; data64 : unsigned(63 downto 0)) return pkt16_t is
    variable p    : pkt16_t := (others => (others => '0'));
    variable addr : unsigned(15 downto 0);
    variable d    : unsigned(63 downto 0) := data64;
  begin
    p(0) := MAGIC_E;
    p(1) := x"01";
    p(2) := x"01"; -- write bit0
    p(3) := x"00";
    addr := (to_unsigned(chan, 8) sll 8) or to_unsigned(cmd, 8);
    p(4) := std_logic_vector(addr(7 downto 0));
    p(5) := std_logic_vector(addr(15 downto 8));
    -- data LE64 into bytes 6..13
    for i in 0 to 7 loop
      p(6 + i) := std_logic_vector(d(8 * i + 7 downto 8 * i));
    end loop;
    return p;
  end function;

  -- RFIC command IDs
  constant CMD_STATUS     : natural := 16#00#;
  constant CMD_INIT       : natural := 16#01#;
  constant CMD_ENABLE     : natural := 16#02#;
  constant CMD_SAMPLERATE : natural := 16#03#;
  constant CMD_FREQUENCY  : natural := 16#04#;
  constant CMD_BANDWIDTH  : natural := 16#05#;
  constant CMD_GAINMODE   : natural := 16#06#;
  constant CMD_GAIN       : natural := 16#07#;

  -- Channels
  constant CH_RX     : natural := 16#00#;
  constant CH_TX     : natural := 16#01#;
  constant CH_SYSTEM : natural := 16#0F#;

  -- Build vectors. For status response, we inject a meaningful status word in data field
  function mk_status_resp (req : pkt16_t; initialized : boolean; last_ok : boolean; qlen : natural) return pkt16_t is
    variable r  : pkt16_t               := mk_success_resp(req);
    variable st : unsigned(63 downto 0) := (others => '0');
  begin
    if (initialized) then
      st(0) := '1';
    end if;
    if (last_ok) then
      st(1) := '1';
    end if;
    st(15 downto 8) := to_unsigned(qlen, 8);
    for i in 0 to 7 loop
      r(6 + i) := std_logic_vector(st(8 * i + 7 downto 8 * i));
    end loop;
    return r;
  end function;

  constant VEC_COUNT : integer := 8;
  type vec_arry_t is array (0 to VEC_COUNT - 1) of vec_t;

  constant vectors : vec_array_t := (
  (name => "STATUS(system)           ",
  req   => mk_rfic_read(CMD_STATUS, CH_SYSTEM),
  resp  => mk_status_resp(mk_rfic_read(CMD_STATUS, CH_SYSTEM), true, true, 0)),
  (name => "INIT(system)             ",
  req   => mk_rfic_write(CMD_INIT, CH_SYSTEM, to_unsigned(0, 64)),
  resp  => mk_success_resp(mk_rfic_write(CMD_INIT, CH_SYSTEM, to_unsigned(0, 64)))),
  (name => "ENABLE(TX)               ",
  req   => mk_rfic_write(CMD_ENABLE, CH_TX, to_unsigned(1, 64)),
  resp  => mk_success_resp(mk_rfic_write(CMD_ENABLE, CH_TX, to_unsigned(1, 64)))),
  (name => "SAMPLERATE(TX)           ",
  req   => mk_rfic_write(CMD_SAMPLERATE, CH_TX, to_unsigned(8000000, 64)),
  resp  => mk_success_resp(mk_rfic_write(CMD_SAMPLERATE, CH_TX, to_unsigned(8000000, 64)))),
  (name => "FREQUENCY(TX)            ",
  req   => mk_rfic_write(CMD_FREQUENCY, CH_TX, to_unsigned(650000000, 64)),
  resp  => mk_success_resp(mk_rfic_write(CMD_FREQUENCY, CH_TX, to_unsigned(650000000, 64)))),
  (name => "BANDWIDTH(TX)            ",
  req   => mk_rfic_write(CMD_BANDWIDTH, CH_TX, to_unsigned(8000000, 64)),
  resp  => mk_success_resp(mk_rfic_write(CMD_BANDWIDTH, CH_TX, to_unsigned(8000000, 64)))),
  (name => "GAINMODE(TX)             ",
  req   => mk_rfic_write(CMD_GAINMODE, CH_TX, to_unsigned(1, 64)),
  resp  => mk_success_resp(mk_rfic_write(CMD_GAINMODE, CH_TX, to_unsigned(1, 64)))),
  (name => "GAIN(TX)                 ",
  req   => mk_rfic_write(CMD_GAIN, CH_TX, to_unsigned(30, 64)),
  resp  => mk_success_resp(mk_rfic_write(CMD_GAIN, CH_TX, to_unsigned(30, 64))))
  );

  -----------------------------------------------------------------------------
  -- tx_start packet builder (target 0x80)
  -----------------------------------------------------------------------------
  function mk_tx_start (len_bytes : unsigned(63 downto 0)) return pkt16_t is
    variable p                      : pkt16_t               := (others => (others => '0'));
    variable d                      : unsigned(63 downto 0) := len_bytes;
  begin
    p(0) := MAGIC_E;
    p(1) := x"80";
    p(2) := x"01";
    p(3) := x"00";
    -- put len in bytes 6..13
    for i in 0 to 7 loop
      p(6 + i) := std_logic_vector(d(8 * i + 7 down to 8 * i));
    end loop;
    return p;
  end function;

  -- expected ACK: magic E, target 80, success bit1 set in flags
  function mk_tx_ack (req : pkt16_t) return pkt16_t is
    variable a              : pkt16_t := (others => (others => '0'));
  begin
    a(0) := MAGIC_E;
    a(1) := x"80";
    a(2) := x"02";
    for i in 0 to 7 loop
      a(6 + i) := req(6 + i);
    end loop;
    return a;
  end function;

begin

  -----------------------------------------------------------------------------
  -- Clock generators
  -----------------------------------------------------------------------------
  ft_clk   <= not ft_clk after FT_CLOCK_PERIOD/2;
  nios_clk <= not nios_clk after NIOS_CLK_PERIOD/2;

  -----------------------------------------------------------------------------
  -- DUT = ft232_interface + ft232_bridge_dispatcher
  -----------------------------------------------------------------------------
  u_if : entity work.ft232_interface
    port map
    (
      ft_clock  => ft_clk,
      reset_n   => reset_n,
      ft_data   => ft_data,
      ft_rxf_n  => rxf_n,
      ft_txe_n  => txe_n,
      ft_rd_n   => rd_n,
      ft_wr_n   => wr_n,
      ft_oe_n   => oe_n,
      ft_siwu_n => open,
      rx_data   => s_rx_data,
      rx_valid  => s_rx_valid,
      rx_ready  => s_rx_ready,
      tx_data   => s_tx_data,
      tx_valid  => s_tx_valid,
      tx_ready  => s_tx_ready
    );

  u_bridge : entity work.ft232_bridge_dispatcher
    port map
    (
      ft_clock        => ft_clk,
      nios_clock      => nios_clk,
      reset_n         => reset_n,
      ftdi_rx_data    => s_rx_data,
      ftdi_rx_valid   => s_rx_valid,
      ftdi_rx_ready   => s_rx_ready,
      ftdi_tx_data    => s_tx_data,
      ftdi_tx_valid   => s_tx_valid,
      ftdi_tx_ready   => s_tx_ready,
      avs_address     => avs_address,
      avs_read        => avs_read,
      avs_write       => avs_write,
      avs_readdata    => avs_readdata,
      avs_writedata   => avs_writedata,
      avs_waitrequest => avs_waitrequest,
      dvbt2_rx_ready  => dvbt2_rx_ready,
      dvbt2_rx_valid  => dvbt2_rx_valid,
      dvbt2_rx_data   => dvbt2_rx_data
    );

  -----------------------------------------------------------------------------
  -- FTDI device model (pin-level)
  -- - Host writes bytes into h2f FIFO (host->FTDI->FPGA)
  -- - FPGA reads them using OE#/RD# while RXF# is low
  -- - FPGA writes bytes using WR# while TXE# low
  -----------------------------------------------------------------------------
  -- Drive RXF_N based on availabilty
  rxfn_drive : process (h2f.used)
  begin
    if (h2f.used > 0) then
      rxf_n <= '0';
    else
      rxf_n <= '1';
    end if;
  end process;

  -- Drive data bus when OE# low (FTDI driving bus)
  ft_data <= ftdi_drive_data when oe_n = '0' else
    (others => 'Z');

  -- Pop host->fpga on RD strobe 
  pop_host : process (ft_clk, reset_n)
    variable b : std_logic_vector(7 downto 0);
  begin
    if (reset_n = '0') then
      ftdi_drive_data <= (others => '0');
    elsif (rising_edge(ft_clk)) then
      if (h2f.used > 0) then
        ftdi_drive_data <= h2f.mem(h2f.rdp);
      end if;

      if ((oe_n = '0') and (rd_n = '0') and (h2f.used > 0)) then
        fifo_pop(h2f, b);
        if (h2f.used > 1) then
          ftdi_drive_data <= h2f.mem((h2f.rdp + 1) mod FTDI_FIFO_DEPTH);
        end if;
      end if;

      if ((wr_n = '0') and (txe_n = '0')) then
        fifo_push(f2h, ft_data);
      end if;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- Avalon helpers for NIOS model
  -----------------------------------------------------------------------------
  procedure avalon_read_word (addr : std_logic_vector(3 downto 0); variable data : out std_logic_vector(31 downto 0)) is
  begin
    avs_address <= addr;
    avs_read    <= '1';
    wait until rising_edge(nios_clk);
    avs_read <= '0';
    data := avs_readdata;
  end procedure;

  procedure avalon_write_word (addr : std_logic_vector(3 downto 0); data : std_logic_vector(31 downto 0)) is
  begin
    avs_address   <= addr;
    avs_writedata <= data;
    avs_write     <= '1';
    wait until rising_edge(nios_clk);
    avs_write <= '0';
  end procedure;

  -----------------------------------------------------------------------------
  -- NIOS model: for each CTRL request, read 4 words and write 4 response words
  -----------------------------------------------------------------------------
  nios_model : process
    variable st             : std_logic_vector(31 downto 0);
    variable w0, w1, w2, w3 : std_logic_vector(31 downto 0);
    variable req_bytes      : pkt16_t;
    variable resp_bytes     : pkt16_t;

    -- decode a 32-bit word into 4bytes le
    procedure word_to_bytes (w : std_logic_vector(31 downto 0); idx : integer; variable outb : inout pkt16_t) is
    begin
      outb(idx + 0) := w(7 downto 0);
      outb(idx + 1) := w(15 downto 8);
      outb(idx + 2) := w(23 downto 16);
      outb(idx + 3) := w(31 downto 24);
    end procedure;

    function bytes_to_word (variable b : pkt16_t; idx : integer) return std_logic_vector is
      variable w : std_logic_vector(31 downto 0);
    begin
      w(7 downto 0)   := b(idx + 0);
      w(15 downto 8)  := b(idx + 1);
      w(23 downto 16) := b(idx + 2);
      w(31 downto 24) := b(idx + 3);
      return w;
    end function;
  begin
    wait until reset_n = '1';

    -- Reactive model  => loops forever, servicing any request packets that arrive
    main_loop : loop
      -- Poll until REQ_USEDW >= 4
      req_poll_loop : loop
        avalon_read_word(x"0", st);
        if (unsigned(st(15 downto 8)) >= 4) then
          exit;
        end if;
        wait until rising_edge(nios_clk);
      end loop; -- req_poll_loop
      -- Read 4 words from REQ_DATA addr 1
      avalon_read_word(x"1", w0);
      avalon_read_word(x"1", w1);
      avalon_read_word(x"1", w2);
      avalon_read_word(x"1", w3);

      word_to_bytes(w0, 0, req_bytes);
      word_to_bytes(w1, 4, req_bytes);
      word_to_bytes(w2, 8, req_bytes);
      word_to_bytes(w3, 12, req_bytes);

      -- If it's a custom target 0x80, the bridge should NOT forward it to NIOS
      -- If it's still the case we produce a response to avoid any deadlock
      if (req_bytes(1) = x"80") then
        resp_bytes    := req_bytes;
        resp_bytes(2) := x"00"; -- Failure
      else
        resp_bytes <= mk_success_resp(req_bytes);
      end if;

      -- Write 4 words to RESP_DATA
      avalon_write_word(x"3", bytes_to_word(resp_bytes, 0));
      avalon_write_word(x"3", bytes_to_word(resp_bytes, 4));
      avalon_write_word(x"3", bytes_to_word(resp_bytes, 8));
      avalon_write_word(x"3", bytes_to_word(resp_bytes, 12));
    end loop; -- main_loop
  end process;

  -----------------------------------------------------------------------------
  -- Test sequencer: drives host traffic into FTDI model and checks results
  -----------------------------------------------------------------------------
  stim : process
    variable got      : pkt16_t;
    variable b        : std_logic_vector(7 downto 0);
    variable req      : pkt16_t;
    variable expected : pkt16_t;

    procedure host_send_pkt (p : pkt16_t) is
    begin
      for i in 0 to 15 loop
        fifo_push(h2f, p(i));
      end loop;
    end procedure;

    procedure host_recv_pkt (variable outp : out pkt16_t) is
    begin
      wait until f2h.used >= 16;
      for i in 0 to 15 loop
        fifo_pop(f2h, b);
        outp(i) := b;
      end loop;
    end procedure;

    procedure assert_pkt_eq (name : string; a : pkt16_t; e : pkt16_t) is
    begin
      for i in 0 to 15 loop
        assert (a(i) = e(i))
        report "Mismatch " & name & " at byte " & integer'image(i)
          severity failure;
      end loop;
    end procedure;

    -- Stream bytes after tx_start
    procedure host_stream_bytes (val : std_logic_vector(7 downto 0); n : natural) is
    begin
      for i in 0 to n - 1 loop
        fifo_push(h2f, val);
      end loop;
    end procedure;

    -- verify DVB-T2 saw N bytes equal to val
    procedure verify_dvbt2_stream (val : std_logic_vector(7 downto 0); n : natural) is
      variable cnt : natural := 0;
    begin
      while (cnt < n) loop
        wait until rising_edge(ft_clk);
        if (dvbt2_rx_valid = '1') then
          assert (dvbt2_rx_data = val)
          report "DVB-T2 byte mismatch at count " & integer'image(cnt)
            severity failure;
          cnt := cnt + 1;
        end if;
      end loop;
    end procedure;

    constant STREAM_LEN : natural := 512;
    variable txreq : pkt16_t;
    variable txack : pkt16_t;

  begin
    reset_n <= '0';
    wait for 200ns;
    reset_n <= '1';

    -- Run CTRL vectors
    for k in 0 to VEC_COUNT-1 loop
        req := vectors(k).req;
        expected := vectors(k).resp;

        host_send_pkt(req);
        host_recv_pkt(got);
        assert_pkt_eq(vectors(k).name, got, expected);
    end loop;

    -- Stream test
    txreq := mk_tx_start(to_unsigned(STREAM_LEN, 64));
    txack := mk_tx_ack(txreq);

    host_send_pkt(txreq);
    host_recv_pkt(got);
    assert_pkt_eq("TX_START_ACK", got, txack);

    -- Now stream data bytes
    host_stream_bytes(x"AA", STREAM_LEN);
    verify_dvbt2_stream(x"AA", STREAM_LEN);

    report "ALL TEST PASSED" severity note;
    wait;
  end process;

end architecture;