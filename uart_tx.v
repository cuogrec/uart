`timescale 1ns / 1ps
module tx(
    input clk,
    input [7:0] data,
    input transmit,
    input reset,
    output reg txd
    );
    
    //internal variables
    reg [3:0] bit_cnt; //count 10 bits
    reg [13:0] baud_cnt; //counter=clock 100mhz/9600
    reg [9:0] shiftright_register; //10 bits that will be serially tx through uart to fpga
    reg state, next_state; //idle mode and transmitting mode
    reg shift; //shift signal to start shifting the bits in the uart
    reg load; // load signal to start loading data into the shiftright register, add start @ stop bit
    reg clear; //reset the bit_counter for uart transmission
    
    //UART TX-TION
    always @(posedge clk)
    begin
        if(reset)
        begin
            state <= 0; //state is idle
            bit_cnt <= 0;// counter for bit tx-tion is reset to 0
            baud_cnt <= 0;
            
        end
        else begin
            baud_cnt <= baud_cnt + 1;
            if(baud_cnt == 10415)
            begin
                state <= next_state;//state changers from idle to tx
                baud_cnt <= 0 ; //reseting counter
                if (load) //if load is asserted
                    shiftright_register <= {1'b1, data, 1'b0};//the data is loaded into the register, 10 bits
                if (clear)//clear is asserted
                    bit_cnt <= 0;
                if(shift) begin//shift is asserted
                    shiftright_register <= shiftright_register >> 1; //start shifting the data
                    bit_cnt <= bit_cnt + 1;
                    end
            end
       end
    end
         
    //Mealy machine, state machine
    always@ (posedge clk)
    begin
        load <= 0; //setting load equal to 0
        shift<= 0; //initially 0
        clear <= 0; //initially 0
        txd <= 1; //when set to 1, there is no tx in progress
        
        case(state) //idle state
        0: begin
            if (transmit) begin //transmit button is pressed
                next_state <= 1; //it moves to tx state
                load <= 1;
                shift <= 0; //no shift at this point
                clear <= 0; //avoid any clearing of any counter
            
            end
            else begin //if tx button is not pressed
            next_state <= 0; //stays at the idle mode
            txd <= 1; //no tx 
            end
        end
        
        1: begin //tx state
        if (bit_cnt  == 10)
            begin
                next_state <= 0;//it should sw from tx mode to idle mode
                clear <= 1; //clear all the counters
             end
        else begin
            next_state <=1; //stay in the tx state
            txd <= shiftright_register[0];
            shift<=1;//continue shifting the data , new bit arrives at the RMB
            end
        end
        default: next_state <= 0;
        endcase
        
    end
           
                    
endmodule  
             
             
module Debounce_Signal#(parameter threshold = 1000000)(
    input clk, //input clk
    input btn,  //input buttons for tx and reset
    output reg transmit //tx signal
    );
    
    reg button_ff1 = 0;
    reg button_ff2 = 0; 
    reg [30:0] cnt = 0; //20 bits count for increment and decrement when button is pressed or released
    //first use 2 ff to synchronize the button signal, "clk", clock domain
    
    always@(posedge clk)
    begin
        button_ff1 <= btn;
        button_ff2 <= button_ff1;
    end
    
    always@(posedge clk)
    begin
        if(button_ff2) //if button_ff2 is high
        begin
            if(~&cnt)//if it isnt at the count limit, make sure you wont count up at the limit, first AND all count and then not the AND
                cnt <= cnt + 1; //when btn is pressed, count up
            end
            else begin
            if (|cnt) //if count has at least 1 in it, making sure no subtract when count is 0
                cnt <= cnt - 1; // when btn is released, count down
            end
            if(cnt > threshold)//if the count is larger than the threshold
                transmit<=1; //debounce signal is 1
            else
                transmit<=0; //debounced signal is 0
            end 
                
endmodule


module Top_Module(
        input [7:0] data,
        input clk,
        input transmit,
        input btn,
        output txd,
        output txd_debug,
        output transmit_debug,
        output btn_debug,
        output clk_debug
        );
        
        wire tx_out;
        tx T1(
        .clk(clk),
        .data(data),
        .transmit(tx_out),
        .reset(1'b0),
        .txd(txd)
        );
        Debounce_Signal DB(clk, btn, tx_out); 
        
        assign txd_debug = txd;
        assign transmit_debug = tx_out;
        assign btn_debug = btn;
        assign clk_debug = clk; 
endmodule 
