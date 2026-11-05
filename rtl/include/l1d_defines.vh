`ifndef L1D_DEFINES_VH
`define L1D_DEFINES_VH
`define L1D_ADDR_W            64
`define L1D_LINE_BYTES        64
`define L1D_NUM_BANKS         4
`define L1D_SETS              64
`define L1D_WAYS              4
`define L1D_WRITE_DATA_WIDTH  64
`define L1D_MEM_SIZE_BITS     2
`define L1D_MASTER_ID_BITS    2
`define L1D_IDX_BITS          3
`define L1D_LSU_BUF_DEPTH     8
`define L1D_TRK_ENTRIES       16
`define L1D_TRK_REFILL_RSV    2
`define L1D_MSHR_ENTRIES      8
`define L1D_MSHR_NC_ENTRIES   2
`define L1D_VC_SLOTS          8
`define L1D_RESP_FIFO_DEPTH   4
`define L1D_REFILL_SKIP       2
`define L1D_SNP_BUF_DEPTH     2
`define L1D_SNP_RESP_DEPTH    2
`define L1D_PF_FIFO_DEPTH     4
`define L1D_SNP_STARVE        8
`define L1D_LOCK_TIMEOUT      1024
`define L1D_RSV_CLR_ON_EVICT  1
`define L1D_AXI_DATA_W        128
`define L1D_AXI_ADDR_W        64
`define L1D_LSU_PORTS         1
`define L1D_HAS_MISS          1
`define L1D_HAS_VC            1
`define L1D_HAS_NC            1
`define L1D_HAS_SNOOP         1
`define L1D_HAS_AMO           1
`define L1D_HAS_PF            0
`define L1D_HAS_ECC           0
`ifndef L1D_DBG_WD
`define L1D_DBG_WD 500
`endif
`define L1D_PARAMS \
    parameter ADDR_W           = `L1D_ADDR_W, \
    parameter LINE_BYTES       = `L1D_LINE_BYTES, \
    parameter NUM_BANKS        = `L1D_NUM_BANKS, \
    parameter SETS             = `L1D_SETS, \
    parameter WAYS             = `L1D_WAYS, \
    parameter WRITE_DATA_WIDTH = `L1D_WRITE_DATA_WIDTH, \
    parameter MEM_SIZE_BITS    = `L1D_MEM_SIZE_BITS, \
    parameter MASTER_ID_BITS   = `L1D_MASTER_ID_BITS, \
    parameter IDX_BITS         = `L1D_IDX_BITS, \
    parameter LSU_BUF_DEPTH    = `L1D_LSU_BUF_DEPTH, \
    parameter TRK_ENTRIES      = `L1D_TRK_ENTRIES, \
    parameter TRK_REFILL_RSV   = `L1D_TRK_REFILL_RSV, \
    parameter MSHR_ENTRIES     = `L1D_MSHR_ENTRIES, \
    parameter MSHR_NC_ENTRIES  = `L1D_MSHR_NC_ENTRIES, \
    parameter VC_SLOTS         = `L1D_VC_SLOTS, \
    parameter RESP_FIFO_DEPTH  = `L1D_RESP_FIFO_DEPTH, \
    parameter REFILL_SKIP      = `L1D_REFILL_SKIP, \
    parameter SNP_BUF_DEPTH    = `L1D_SNP_BUF_DEPTH, \
    parameter SNP_RESP_DEPTH   = `L1D_SNP_RESP_DEPTH, \
    parameter PF_FIFO_DEPTH    = `L1D_PF_FIFO_DEPTH, \
    parameter SNP_STARVE       = `L1D_SNP_STARVE, \
    parameter LOCK_TIMEOUT     = `L1D_LOCK_TIMEOUT, \
    parameter RSV_CLR_ON_EVICT = `L1D_RSV_CLR_ON_EVICT, \
    parameter HAS_SNOOP        = `L1D_HAS_SNOOP, \
    parameter HAS_AMO          = `L1D_HAS_AMO, \
    parameter AXI_DATA_W       = `L1D_AXI_DATA_W, \
    parameter AXI_ADDR_W       = `L1D_AXI_ADDR_W
`define L1D_PARAMS_PASS \
    .ADDR_W(ADDR_W), \
    .LINE_BYTES(LINE_BYTES), \
    .NUM_BANKS(NUM_BANKS), \
    .SETS(SETS), \
    .WAYS(WAYS), \
    .WRITE_DATA_WIDTH(WRITE_DATA_WIDTH), \
    .MEM_SIZE_BITS(MEM_SIZE_BITS), \
    .MASTER_ID_BITS(MASTER_ID_BITS), \
    .IDX_BITS(IDX_BITS), \
    .LSU_BUF_DEPTH(LSU_BUF_DEPTH), \
    .TRK_ENTRIES(TRK_ENTRIES), \
    .TRK_REFILL_RSV(TRK_REFILL_RSV), \
    .MSHR_ENTRIES(MSHR_ENTRIES), \
    .MSHR_NC_ENTRIES(MSHR_NC_ENTRIES), \
    .VC_SLOTS(VC_SLOTS), \
    .RESP_FIFO_DEPTH(RESP_FIFO_DEPTH), \
    .REFILL_SKIP(REFILL_SKIP), \
    .SNP_BUF_DEPTH(SNP_BUF_DEPTH), \
    .SNP_RESP_DEPTH(SNP_RESP_DEPTH), \
    .PF_FIFO_DEPTH(PF_FIFO_DEPTH), \
    .SNP_STARVE(SNP_STARVE), \
    .LOCK_TIMEOUT(LOCK_TIMEOUT), \
    .RSV_CLR_ON_EVICT(RSV_CLR_ON_EVICT), \
    .HAS_SNOOP(HAS_SNOOP), \
    .HAS_AMO(HAS_AMO), \
    .AXI_DATA_W(AXI_DATA_W), \
    .AXI_ADDR_W (AXI_ADDR_W)
`endif
