// File: Vortex/hw/rtl/fpu/VX_fpu_dpi_wrapper_pkg.sv

package fpu_dpi_wrapper_pkg;

  import "DPI-C" function longint dpi_fsqrt (longint a);
  import "DPI-C" function longint dpi_fdiv  (longint a, longint b);
  import "DPI-C" function longint dpi_fmadd (longint a, longint b, longint c);

  function automatic longint fpu_fsqrt (longint a);
    return dpi_fsqrt(a);
  endfunction

  function automatic longint fpu_fdiv (longint a, longint b);
    return dpi_fdiv(a, b);
  endfunction

  function automatic longint fpu_fmadd (longint a, longint b, longint c);
    return dpi_fmadd(a, b, c);
  endfunction

endpackage
