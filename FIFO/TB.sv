class transaction;
    rand bit oper;
    bit clk;
    bit rst;
    bit wr;
    bit rd;
    bit [7:0] din;
    bit [7:0] dout;
    bit full;
    bit empty;

    constraint oper_ctrl{
        oper dist {1 :/ 50 , 0 :/ 50};
    };
endclass

class generator;
    transaction tr;
    mailbox #(transaction) mbx;
    int count = 0;
    int i = 0;

    event next;
    event done;

    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
        tr = new();
    endfunction

    task run();
        repeat(count)begin
            assert (tr.randomize) else $error("Transaction randomization failed");
            mbx.put(tr);
            i++;
            $display("[GEN]: oper: %d, iteration: %d", tr.oper, i);
            @(next);
        end -> done;
    endtask
endclass

class driver;
    virtual fifo_if fif;
    mailbox #(transaction) mbx;
    transaction tr;

    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
    endfunction

    task reset();
        fif.rst <= 1'b1;
        fif.wr <= 1'b0;
        fif.rd <= 1'b0;
        fif.din <= 0;
        repeat(5) @(posedge fif.clk);
        fif.rst <= 1'b0;
        $display("[DRV] : DUT Reset Done");
        $display("------------------------------------------");
    endtask

    // Write data to the FIFO
    task write();
        @(posedge fif.clk);
        fif.rst <= 1'b0;
        fif.rd <= 1'b0;
        fif.wr <= 1'b1;
        fif.din <= $urandom_range(1, 10);
        @(posedge fif.clk);
        fif.wr <= 1'b0;
        $display("[DRV] : DATA WRITE  data : %0d", fif.din);  
        @(posedge fif.clk);
    endtask
    
    // Read data from the FIFO
    task read();  
        @(posedge fif.clk);
        fif.rst <= 1'b0;
        fif.rd <= 1'b1;
        fif.wr <= 1'b0;
        @(posedge fif.clk);
        fif.rd <= 1'b0;      
        $display("[DRV] : DATA READ");  
        @(posedge fif.clk);
    endtask

    task run();
        forever begin
            mbx.get(tr);
            if(tr.oper == 1'b1)begin //write operation
                write();
            end else if (tr.oper == 1'b0) begin //read operation
                read();
            end
        end 
    endtask
endclass

class monitor;
 
  virtual fifo_if fif;     // Virtual interface to the FIFO
  mailbox #(transaction) mbx;  // Mailbox for communication
  transaction tr;          // Transaction object for monitoring
  
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;     
  endfunction;
 
  task run();
    tr = new();
    
    forever begin
      repeat (2) @(posedge fif.clk);
      tr.wr = fif.wr;
      tr.rd = fif.rd;
      tr.din = fif.din;
      tr.full = fif.full;
      tr.empty = fif.empty; 
      @(posedge fif.clk);
      tr.dout = fif.dout;
    
      mbx.put(tr);
      $display("[MON] : Wr:%0d rd:%0d din:%0d dout:%0d full:%0d empty:%0d", tr.wr, tr.rd, tr.din, tr.dout, tr.full, tr.empty);
    end
    
  endtask
endclass

class scoreboard;
    event next;
    bit [7:0] din[$];
    transaction tr;
    bit [7:0] ref_rdata;
    mailbox #(transaction) mbx;
    int err = 0;

    function new(mailbox #(transaction) mbx);
        this.mbx = mbx;
    endfunction

    task run();
        forever begin
            mbx.get(tr);
            if(tr.wr == 1'b1) begin
                if(tr.full == 1'b0) begin
                    din.push_back(tr.din);
                end else begin // fifo is full
                    $display("[SCR]: FIFO is full!");
                end
            end else if (tr.rd == 1'b1) begin
                if(tr.empty == 1'b0) begin 
                    ref_rdata = din.pop_front();
                    if(ref_rdata == tr.dout) begin 
                        $display("[SCR]: DATA MATCH");
                    end else begin
                        $display("[SCR]: DATA MISSMATCH");
                        err++;
                    end
                end else if (tr.empty == 1'b1) begin
                    $display("[SCR]: Empty FIFO");
                end
            end
            -> next;
        end
    endtask
endclass

class environment;
 
  generator gen;
  driver drv;
  monitor mon;
  scoreboard sco;
  mailbox #(transaction) gdmbx;  // Generator + Driver mailbox
  mailbox #(transaction) msmbx;  // Monitor + Scoreboard mailbox
  event nextgs;
  virtual fifo_if fif;
  
  function new(virtual fifo_if fif);
    gdmbx = new();
    gen = new(gdmbx);
    drv = new(gdmbx);
    msmbx = new();
    mon = new(msmbx);
    sco = new(msmbx);
    this.fif = fif;
    drv.fif = this.fif;
    mon.fif = this.fif;
    gen.next = nextgs;
    sco.next = nextgs;
  endfunction
  
  task pre_test();
    drv.reset();
  endtask
  
  task test();
    fork
      gen.run();
      drv.run();
      mon.run();
      sco.run();
    join_any
  endtask
  
  task post_test();
    wait(gen.done.triggered);  
    $display("---------------------------------------------");
    $display("Error Count :%0d", sco.err);
    $display("---------------------------------------------");
    $finish();
  endtask
  
  task run();
    pre_test();
    test();
    post_test();
  endtask
  
endclass

module tb;
    fifo_if fif();
    FIFO dut(
        .clk(fif.clk),
        .rst(fif.rst),
        .wr(fif.wr),
        .rd(fif.rd),
        .din(fif.din),
        .dout(fif.dout),
        .full(fif.full),
        .empty(fif.empty)
    );

    initial begin
        fif.clk <= 0;
    end
    
    always #10 fif.clk <= ~fif.clk;
        
    environment env;
        
    initial begin
        env = new(fif);
        env.gen.count = 10;
        env.run();
    end
        
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars;
    end
    
endmodule