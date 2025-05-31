`define     IP_VER      32'h000
`define     POINTER     32'h100
`define     START_ADDR  32'h104
`define     STAT_ADDR   32'h108
 
`define     TIMEOUT_CYCLE   200000000
module DMAC_TOP_TB ();
 
    reg                     clk;
    reg                     rst_n;
 
    // clock generation
    initial begin
        clk                     = 1'b0;
 
        forever #10 clk         = !clk;
    end
 
    // reset generation
    initial begin
        rst_n                   = 1'b0;     // active at time 0
 
        repeat (3) @(posedge clk);          // after 3 cycles,
        rst_n                   = 1'b1;     // release the reset
    end
 
    //set random seed
    initial begin
        int seed = 12345;
    int random_value;
        random_value = $urandom(seed);
    end
 
    // enable waveform dump
    initial begin
        $dumpvars(0, u_DUT);
        $dumpfile("dump.vcd");
    end
    // timeout
    initial begin
        #`TIMEOUT_CYCLE $display("Timeout!");
        $finish;
    end
 
    APB                         apb_if  (.clk(clk));
 
    AXI_AW_CH                   aw_ch   (.clk(clk));
    AXI_W_CH                    w_ch    (.clk(clk));
    AXI_B_CH                    b_ch    (.clk(clk));
    AXI_AR_CH                   ar_ch   (.clk(clk));
    AXI_R_CH                    r_ch    (.clk(clk));
 
    bit [31:0]                  gather_addr_queue[$];
    int                         gather_wdata_queue[$];            
    int                         gather_blen_queue[$];
 
    bit [31:0]                  scatter_addr_queue[$];
    int                         scatter_blen_queue[$];
    int                         scatter_rdata_queue[$];
 
    task test_init();
        int data;
        apb_if.init();
 
        @(posedge rst_n);                   // wait for a release of the reset
        repeat (10) @(posedge clk);         // wait another 10 cycles
 
        apb_if.read(`IP_VER, data);
        $display("---------------------------------------------------");
        $display("IP version: %x", data);
        $display("---------------------------------------------------");
 
        $display("---------------------------------------------------");
        $display("Reset value test");
        apb_if.read(`POINTER, data);
        if (data===0)
            $display("SGDMA_START_POINTER(pass): %x", data);
        else begin
            $display("SGDMA_START_POINTER(fail): %x", data);
            @(posedge clk);
            $finish;
        end
        apb_if.read(`STAT_ADDR, data);
        if (data===1)
            $display("SGDMA_STATUS(pass): %x", data);
        else begin
            $display("SGDMA_STATUS(fail): %x", data);
            @(posedge clk);
            $finish;
        end
        $display("---------------------------------------------------");
    endtask

 
    task make_descriptor_gather(input int start_pointer, input int descriptor_cnt, input int write_chain_num);
        int address;
        int byte_len;
        int read_or_write;
        int next_pointer;
 
        int stride;
        int sum_of_byte_len;
        int current_pointer;
 
        int words;
        int base_word_count;
        int remain_word;
 
        int word;
        // int write_chunk [write_chain_num];
        int write_chunk [];
 
        write_chunk = new[write_chain_num];
        stride                  = $urandom_range(8, 2) * 32;
        sum_of_byte_len         = 0;
        current_pointer         = start_pointer;
        $display("---------------------------------------------------");
        $display("Write descriptor chain to memory");
        $display("Case: Gathering");
        $display("Start Pointer: %x Chain Length: %x", start_pointer, descriptor_cnt);
 
        // write descriptor and data in memory without last descriptor
        for (int i = 0; i < descriptor_cnt - write_chain_num; i++) begin
            address             = $urandom_range(8, 0) * 32 + i * 2048;
            gather_addr_queue.push_back(address);
            byte_len            = $urandom_range(32, 16) * 4;
            gather_blen_queue.push_back(byte_len);
            read_or_write       = 0; // read
            next_pointer        = current_pointer + stride;
 
            // write data in "address"
            for (int j = address; j < (address + byte_len); j = j + 4) begin
                word                = $random;
                u_mem.write_word(j, word);
                gather_wdata_queue.push_back(word);
            end
 
            // write descriptor in "current_pointer"
            u_mem.write_word(current_pointer, address);
            u_mem.write_word(current_pointer + 4, byte_len);
            u_mem.write_word(current_pointer + 8, read_or_write);
            u_mem.write_word(current_pointer + 12, next_pointer);
 
            // update total byte_len
            sum_of_byte_len     = sum_of_byte_len + byte_len;
 
            // update current pointer as a next pointer
            current_pointer     = next_pointer;
        end
 
        base_word_count = (sum_of_byte_len / 4) / write_chain_num;
        remain_word     = (sum_of_byte_len / 4) % write_chain_num;
 
 
        for (int i = 0; i < write_chain_num; i++) begin
            words           = base_word_count;
            if (i < remain_word)
                words += 1;
            write_chunk[i] = words * 4; // byte
        end        
 
        for (int i = 0; i < write_chain_num; i++) begin
            // words           = base_word_count;
            // if (i < remain_word)
            //     words += 1;
            // write_chunk[i] = words * 4; // byte
            // write descriptor
            address      = $urandom_range(8, 0) * 32 + (descriptor_cnt - write_chain_num + i) * 2048;
            byte_len     = write_chunk[i];
            read_or_write = 1; // write
 
            if (i != write_chain_num - 1)
                next_pointer = current_pointer + stride;
            else
                next_pointer = start_pointer;
 
            // write descriptor to memory
            u_mem.write_word(current_pointer, address);
            u_mem.write_word(current_pointer + 4, byte_len);
            u_mem.write_word(current_pointer + 8, read_or_write);
            u_mem.write_word(current_pointer + 12, next_pointer);
 
            current_pointer = next_pointer;
        end
           
    endtask
 
    task make_descriptor_scatter(input int start_pointer, input int descriptor_cnt);
        int address;
        int byte_len;
        int read_or_write;
        int next_pointer;
 
        int stride;
        int sum_of_byte_len;
        int current_pointer;
 
        int word;
 
        stride                  = $urandom_range(8, 2) * 32;
        sum_of_byte_len         = 0;
        current_pointer         = start_pointer + stride;
        $display("Write descriptor chain to memory");
        $display("Case: Scattering");
        $display("Start Pointer: %x Chain Length: %x", start_pointer, descriptor_cnt);
        $display("---------------------------------------------------");
 
        // write descriptors and data in to memory without firt descriptor
        for (int i = 1; i < descriptor_cnt; i++) begin
            address                 = $urandom_range(8, 0) * 8 + (i + 2) * 2048;
            scatter_addr_queue.push_back(address);
            byte_len                = $urandom_range(32, 16) * 4;
            scatter_blen_queue.push_back(byte_len);
            read_or_write           = 1; // write
            next_pointer            = current_pointer + stride;
            if (i == descriptor_cnt - 1) begin
                next_pointer            = start_pointer;
            end
 
            // write descriptor in "current_pointer"
            u_mem.write_word(current_pointer, address);
            u_mem.write_word(current_pointer + 4, byte_len);
            u_mem.write_word(current_pointer + 8, read_or_write);
            u_mem.write_word(current_pointer + 12, next_pointer);
 
            // update total byte_len
            sum_of_byte_len         = sum_of_byte_len + byte_len;
 
            // update current pointer as a next pointer
            current_pointer         = next_pointer;
        end
 
        // write first descriptor
        address             = $urandom_range(8, 0) * 8;
        byte_len            = sum_of_byte_len;
        read_or_write       = 0; // read
        next_pointer        = start_pointer + stride;
 
        // write descriptor in "start_pointer"
        u_mem.write_word(start_pointer, address);
        u_mem.write_word(start_pointer + 4, byte_len);
        u_mem.write_word(start_pointer + 8, read_or_write);
        u_mem.write_word(start_pointer + 12, next_pointer);
 
        for (int j = address; j < (address + byte_len); j = j + 4) begin
            word                = $random;
            u_mem.write_word(j, word);
            scatter_rdata_queue.push_back(word);
        end
    endtask
 
    task start_dma(input int start_pointer, output time runtime);
        int data;
        realtime elapsed_time;
 
        $display("---------------------------------------------------");
        $display("Configuration test");
        apb_if.write(`POINTER, start_pointer);
        apb_if.read(`POINTER, data);
        if (data===start_pointer)
            $display("SGDMA_START_POINTER(pass): %x", data);
        else begin
            $display("SGDMA_START_POINTER(fail): %x", data);
            @(posedge clk);
            $finish;
        end
 
        $display("---------------------------------------------------");
        $display("DMA start");
        apb_if.write(`START_ADDR, 32'h1);
        elapsed_time = $realtime;
 
        data = 0;
        while (data!=1) begin
            apb_if.read(`STAT_ADDR, data);
            repeat (100) @(posedge clk);
        end
        @(posedge clk);
        elapsed_time = $realtime - elapsed_time;
        $timeformat(-9, 0, " ns", 10);
 
        $display("---------------------------------------------------");
        $display("DMA completed");
        $display("Elapsed time for DMA: %t", elapsed_time);
        $display("---------------------------------------------------");
 
        runtime = elapsed_time;
    endtask
 
    task check_gather(input int start_pointer, input int descriptor_cnt , input int write_chain_cnt);
        int src_addr;
        int dst_addr;
        int length;
 
        int pointer;
        int pointer_n;
 
        int src_data[2048];
        int write_pointer;
        int read_pointer;
 
        int _address;
        int _byte_len;
        bit [31:0] temp_data;
        bit [1023:0] data;
        bit [15359:0] answer_data;
        int answer_data_pointer;
        bit [15359:0] result_data;
        int write_offset;

        src_addr            = 0;
        dst_addr            = 0;
        length              = 0;
 
        pointer             = start_pointer;
        pointer_n           = 0;
 
        _address            = 0;
        _byte_len           = 0;
        data                = 'h0;
        answer_data         = 'h0;
        answer_data_pointer = 0;
        result_data         = 'h0;
 
        for (int max_byte = 0; max_byte < 2048; max_byte++) begin
            src_data[max_byte]      = 0;
        end
        write_pointer       = 0;
        read_pointer        = 0;
 
        $display("---------------------------------------------------");
        $display("Verify Gathering Operation Result");
        $display("---------------------------------------------------");
 
       
        for (int i = 0; i < descriptor_cnt - write_chain_cnt; i++) begin
            src_addr        = u_mem.read_word(pointer);
            length          = u_mem.read_word(pointer + 4);
            pointer_n       = u_mem.read_word(pointer + 12);
 
            for (int j = 0; j < length; j = j + 4) begin
                src_data[write_pointer]         = u_mem.read_word(src_addr + j);
                write_pointer++;
            end
            pointer         = pointer_n;
        end
 
        for (int i = 0; i < descriptor_cnt - write_chain_cnt; i++) begin
            _address = gather_addr_queue.pop_front();
            _byte_len = gather_blen_queue.pop_front();
            data = 'h0;
            for(int j = 0; j < _byte_len/4; j = j + 1) begin
                    temp_data = gather_wdata_queue.pop_front();
                    data[(j*32)+:32] = temp_data;
                    answer_data[answer_data_pointer*32+:32] = temp_data;
                    answer_data_pointer++;
            end
            //$display("%dth Read Data | [Address: 0x%x] | [Data: 0x%0x]", i, _address, data);
        end
        
       
        write_offset = 0;
        for (int i = 0; i < write_chain_cnt; i++) begin
            dst_addr        = u_mem.read_word(pointer);
            length          = u_mem.read_word(pointer + 4);
            pointer_n       = u_mem.read_word(pointer + 12);
            for (int k = 0; k < length; k = k + 4) begin
                result_data[write_offset*32 +: 32] = u_mem.read_word(dst_addr + k);
                write_offset++;
            end
            pointer = pointer_n;
        end
        
 
        $display("---------------------------------------------------");
        $display("1. Compare your Gathered Data with the answer");
        $display("---------------------------------------------------");
 
        if (answer_data !== result_data) begin
            $display("    - Mismatch!");
            $display("      - Answer : 0x%0x", answer_data);
            $display("      - Result : 0x%0x", result_data);
            $finish;
        end else begin
            $display("    - Match!");
            $display("      - Answer : 0x%0x", answer_data);
            $display("      - Result : 0x%0x", result_data);
        end
 
        gather_addr_queue.delete();
        gather_blen_queue.delete();
        gather_wdata_queue.delete();
 
        $display("---------------------------------------------------\n");
    endtask
 
    task check_scatter(input int start_pointer, input int descriptor_cnt);
        int src_addr;
        int dst_addr;
        int length;
 
        int pointer;
        int pointer_n;
 
        int dst_data [2048];
        int write_pointer = 0;
        int read_pointer = 0;
 
        bit [1023:0] scatter_wdata;
        bit [15359:0] result_data;
        int word_data;
        int result_data_pointer;
        bit [15359:0] answer_data;
 
        src_addr            = 0;
        dst_addr            = 0;
        length              = 0;
 
        pointer         = start_pointer;
        pointer_n       = u_mem.read_word(start_pointer + 12);
        pointer         = pointer_n;
 
        scatter_wdata       = 'h0;
        result_data         = 'h0;
        result_data_pointer = 0;
        answer_data         = 'h0;
 
        for (int max_byte=0; max_byte < 2048; max_byte++) begin
            dst_data[max_byte]      = 0;
        end
        write_pointer       = 0;
        read_pointer        = 0;
 
        $display("---------------------------------------------------");
        $display("Verify Scattering Operation Result");
        $display("---------------------------------------------------");
 
        $display("---------------------------------------------------");
        $display("1. Compare your Scattered Data with the answer");
        $display("---------------------------------------------------");
 
        for (int i = 0; i < descriptor_cnt - 1; i++) begin
           
 
            dst_addr        = u_mem.read_word(pointer);
            length          = u_mem.read_word(pointer + 4);
            pointer_n       = u_mem.read_word(pointer + 12);
 
            for (int j = 0; j < length; j = j + 4) begin
                dst_data[write_pointer]         = u_mem.read_word(dst_addr + j);
                write_pointer++;
            end
            pointer         = pointer_n;
 
            word_data = 'h0;
            for (int j = 0; j < length; j = j + 4) begin
                word_data = u_mem.read_word(dst_addr + j);
                scatter_wdata[(j/4)*32+:32] = word_data;
                answer_data[(j/4)*32+:32] = scatter_rdata_queue.pop_front();
            end
 
            $display("  - %1dth Scattered Data",i);
            if (answer_data !== scatter_wdata) begin
                $display("    - Mismatch!");
                $display("      - Answer : 0x%0x", answer_data);
                $display("      - Result : 0x%0x\n", scatter_wdata);
                $finish;
            end else begin
                $display("    - Match!");
                $display("      - Answer : 0x%0x", answer_data);
                $display("      - Result : 0x%0x\n", scatter_wdata);
            end
 
            scatter_wdata = 'h0;
            answer_data = 'h0;
        end
        $display("---------------------------------------------------\n");
    endtask
 
    int descriptor_start_pointer;
    int descriptor_length;
    int write_chain_cnt;
 
    time time_0, time_1, time_2, time_3, time_4, time_5;
    // main
    initial begin
        test_init();
 
        descriptor_start_pointer        = 'h0000_8000;
        descriptor_length               = 8;
        write_chain_cnt                 = 1;
        $display("===================================================");
        $display("= 1st trial");
        $display("===================================================");
        make_descriptor_gather(descriptor_start_pointer, descriptor_length, write_chain_cnt);
        start_dma(descriptor_start_pointer, time_0);
        check_gather(descriptor_start_pointer, descriptor_length, write_chain_cnt);
 
        descriptor_start_pointer        = 'h0000_9000;
        descriptor_length               = 8;
        $display("===================================================");
        $display("= 2nd trial");
        $display("===================================================");
        make_descriptor_scatter(descriptor_start_pointer, descriptor_length);
        start_dma(descriptor_start_pointer, time_1);
        check_scatter(descriptor_start_pointer, descriptor_length);
 
        descriptor_start_pointer        = 'h0000_A000;
        descriptor_length               = 12;
        write_chain_cnt                 = 2;
        $display("===================================================");
        $display("= 3rd trial");
        $display("===================================================");
        make_descriptor_gather(descriptor_start_pointer, descriptor_length, write_chain_cnt);
        start_dma(descriptor_start_pointer, time_2);
        check_gather(descriptor_start_pointer, descriptor_length, write_chain_cnt);
 
        descriptor_start_pointer        = 'h0000_B000;
        descriptor_length               = 12;
        $display("===================================================");
        $display("= 4th trial");
        $display("===================================================");
        make_descriptor_scatter(descriptor_start_pointer, descriptor_length);
        start_dma(descriptor_start_pointer, time_3);
        check_scatter(descriptor_start_pointer, descriptor_length);
 
        descriptor_start_pointer        = 'h0000_C000;
        descriptor_length               = 16;
        write_chain_cnt                 = 4;
        $display("===================================================");
        $display("= 5th trial");
        $display("===================================================");
        make_descriptor_gather(descriptor_start_pointer, descriptor_length, write_chain_cnt);
        start_dma(descriptor_start_pointer, time_4);
        check_gather(descriptor_start_pointer, descriptor_length, write_chain_cnt);
 
        descriptor_start_pointer        = 'h0000_D000;
        descriptor_length               = 16;
        $display("===================================================");
        $display("= 6th trial");
        $display("===================================================");
        make_descriptor_scatter(descriptor_start_pointer, descriptor_length);
        start_dma(descriptor_start_pointer, time_5);
        check_scatter(descriptor_start_pointer, descriptor_length);
 
        $display("test completed");
    $display("<< Test 1 time: %d (ns)", time_0);
    $display("<< Test 2 time: %d (ns)", time_1);
    $display("<< Test 3 time: %d (ns)", time_2);
    $display("<< Test 4 time: %d (ns)", time_3);
    $display("<< Test 5 time: %d (ns)", time_4);
    $display("<< Test 6 time: %d (ns)", time_5);
        $finish;
    end
 
 
    AXI_SLAVE   u_mem (
        .clk                    (clk),
        .rst_n                  (rst_n),
 
        .aw_ch                  (aw_ch),
        .w_ch                   (w_ch),
        .b_ch                   (b_ch),
        .ar_ch                  (ar_ch),
        .r_ch                   (r_ch)
    );
 
    SGDMAC_TOP  u_DUT (
        .clk                    (clk),
        .rst_n                  (rst_n),
 
        // APB interface
        .psel_i                 (apb_if.psel),
        .penable_i              (apb_if.penable),
        .paddr_i                (apb_if.paddr[11:0]),
        .pwrite_i               (apb_if.pwrite),
        .pwdata_i               (apb_if.pwdata),
        .pready_o               (apb_if.pready),
        .prdata_o               (apb_if.prdata),
        .pslverr_o              (apb_if.pslverr),
 
        // AXI AW channel
        .awid_o                 (aw_ch.awid),
        .awaddr_o               (aw_ch.awaddr),
        .awlen_o                (aw_ch.awlen),
        .awsize_o               (aw_ch.awsize),
        .awburst_o              (aw_ch.awburst),
        .awvalid_o              (aw_ch.awvalid),
        .awready_i              (aw_ch.awready),
 
        // AXI W channel
        .wid_o                  (w_ch.wid),
        .wdata_o                (w_ch.wdata),
        .wstrb_o                (w_ch.wstrb),
        .wlast_o                (w_ch.wlast),
        .wvalid_o               (w_ch.wvalid),
        .wready_i               (w_ch.wready),
 
        // AXI B channel
        .bid_i                  (b_ch.bid),
        .bresp_i                (b_ch.bresp),
        .bvalid_i               (b_ch.bvalid),
        .bready_o               (b_ch.bready),
 
        // AXI AR channel
        .arid_o                 (ar_ch.arid),
        .araddr_o               (ar_ch.araddr),
        .arlen_o                (ar_ch.arlen),
        .arsize_o               (ar_ch.arsize),
        .arburst_o              (ar_ch.arburst),
        .arvalid_o              (ar_ch.arvalid),
        .arready_i              (ar_ch.arready),
 
        // AXI R channel
        .rid_i                  (r_ch.rid),
        .rdata_i                (r_ch.rdata),
        .rresp_i                (r_ch.rresp),
        .rlast_i                (r_ch.rlast),
        .rvalid_i               (r_ch.rvalid),
        .rready_o               (r_ch.rready)
    );
 
endmodule
