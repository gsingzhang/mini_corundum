// coverage_summary.sv - Generates code coverage summary at simulation end

class ludp_coverage_printer;
    function void print_coverage_summary();
        string cov_options;
        int cov_handle;

        $display(" ");
        $display("========================================");
        $display("  Code Coverage Summary");
        $display("========================================");
        $display(" ");

        // Print overall line/cond/branch coverage
        $coverage("get_coverage", cov_handle, "line+cond+branch");
        $display(" ");
        $display("Coverage data available in VCS database");
        $display("========================================");
    endfunction
endclass
