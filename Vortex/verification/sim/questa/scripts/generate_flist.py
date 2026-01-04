#!/usr/bin/env python3
"""
Generate RTL file list for QuestaSim compilation
"""
import os
import sys

def find_rtl_files(rtl_dir, xlen=32):
    """Find all RTL files in proper compilation order"""
    
    files = []
    
    # Add package files first (they must be compiled before other files)
    packages = [
        f"{rtl_dir}/VX_gpu_pkg.sv",
        f"{rtl_dir}/VX_trace_pkg.sv",
        f"{rtl_dir}/fpu/VX_fpu_pkg.sv",
    ]
    
    for pkg in packages:
        if os.path.exists(pkg):
            files.append(pkg)
    
    # Add interface files
    intf_dir = f"{rtl_dir}/interfaces"
    if os.path.isdir(intf_dir):
        for f in sorted(os.listdir(intf_dir)):
            if f.endswith('.sv') or f.endswith('.v'):
                files.append(os.path.join(intf_dir, f))
    
    # Add library files
    libs_dir = f"{rtl_dir}/libs"
    if os.path.isdir(libs_dir):
        for root, dirs, filenames in os.walk(libs_dir):
            for f in sorted(filenames):
                if f.endswith('.sv') or f.endswith('.v'):
                    files.append(os.path.join(root, f))
    
    # Add core files
    core_dirs = ['core', 'mem', 'cache', 'fpu']
    for subdir in core_dirs:
        full_dir = f"{rtl_dir}/{subdir}"
        if os.path.isdir(full_dir):
            for root, dirs, filenames in os.walk(full_dir):
                for f in sorted(filenames):
                    if f.endswith('.sv') or f.endswith('.v'):
                        if not f.endswith('_pkg.sv'):  # Skip packages (already added)
                            files.append(os.path.join(root, f))
    
    # Add top-level files
    top_files = [
        f"{rtl_dir}/VX_socket.sv",
        f"{rtl_dir}/VX_cluster.sv",
        f"{rtl_dir}/Vortex.sv",
    ]
    
    for tf in top_files:
        if os.path.exists(tf):
            files.append(tf)
    
    return files

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: generate_flist.py <rtl_dir> <output_file> [xlen]")
        sys.exit(1)
    
    rtl_dir = sys.argv[1]
    output_file = sys.argv[2]
    xlen = int(sys.argv[3]) if len(sys.argv) > 3 else 32
    
    files = find_rtl_files(rtl_dir, xlen)
    
    with open(output_file, 'w') as f:
        for file in files:
            f.write(f"{file}\n")
    
    print(f"Generated {output_file} with {len(files)} files")