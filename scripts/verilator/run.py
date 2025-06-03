import sys, os





def main():
    # STEP
    if len(sys.argv) <= 3:
        print("3 arguments needed!")
        print("Usage: " + sys.argv[0] + " top_verilog.v includeDir topModule [define]")
        exit()
    if len(sys.argv) == 4:
        _, top_verilog, includeDir, topModule = sys.argv
        define = ""
    else:
        _, top_verilog, includeDir, topModule, define = sys.argv

    build_folder_name = ".".join("-".join(top_verilog.split("/")[1:]).split(".")[0:-1])

    # STEP: clean up
    command = "mkdir -p build"
    print("[command to run]: ", command)
    assert os.system(command) == 0

    command = f"rm -rf 'build/{build_folder_name}'"
    print("[command to run]: ", command)
    assert os.system(command) == 0

    entry_file = os.path.join(os.getcwd(), "scripts/verilator/top.sv")
    # STEP: compile
    with open(entry_file, "w") as top:
        top.write(f'`include "{top_verilog}"')

    command = (
        f"verilator --cc --Mdir build/{build_folder_name}"
        f" -I{includeDir} -top {topModule} +define{define}"
        f" --prefix Vtop -Wno-fatal --trace --exe --build -j 4"
        f" '{entry_file}'"
        f" '{os.path.join(os.getcwd(), "scripts/verilator/main.cpp")}'"
    )
    print("[command to run]: ", command)
    assert os.system(command) == 0

    command = f"rm '{entry_file}'"
    print("[command to run]: ", command)
    assert os.system(command) == 0

    # STEP: run
    command = f"build/{build_folder_name}/Vtop {build_folder_name}"
    print("[command to run]: ", command)
    assert os.system(command) == 0


if __name__ == "__main__":
    main()
