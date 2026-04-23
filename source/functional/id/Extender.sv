module Extender
#(
    // Placeholder kept for compatibility with older datapath experiments that
    // used a separate immediate-extension unit. The current decoder generates
    // immediates directly, so this module intentionally has no ports.
    parameter bit ENABLED = 1'b0
)
(
    // Intentionally empty.
);

endmodule
