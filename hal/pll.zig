pub const Pll = extern struct {
    cs: CS,
    pwr: Pwr,
    fbdiv_int: FbdivInt,
    prim: Prim,
};

pub const CS = packed struct(u32) {
    ref_div: u6,
    reserved_1: u2,
    bypass: u1,
    reserved_2: u22,
    lock: u1,
};

pub const Pwr = packed struct(u32) {
    pll_pd: u1,
    reserved_1: u1,
    dsm_pd: u1,
    post_div_pd: u1,
    reserved_2: u1,
    vco_pd: u1,
    reserved_3: u26,
};

// NOTE: this PLL does not support fractional division
pub const FbdivInt = packed struct(u32) {
    constraints: u12,
    reserved: u20,
};

pub const Prim = packed struct(u32) {
    reserved_1: u12,
    post_div_2: u3,
    reserved_2: u1,
    post_div_1: u3,
    reserved_3: u13,
};
