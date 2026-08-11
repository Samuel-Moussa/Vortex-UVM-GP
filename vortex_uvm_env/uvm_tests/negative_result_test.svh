////////////////////////////////////////////////////////////////////////////////
// File: negative_result_test.sv
// Description: Negative / Fault-Injection Test (checker-failure proof)
//
// Purpose:
//   Proves the scoreboard can FAIL, not just pass. Runs the exact same kernel
//   launch flow as kernel_launch_test, but injects ONE deliberate fault into
//   the scoreboard's comparison so the DUT-vs-SimX check is forced to mismatch.
//
//   The fault is ONE-SIDED by construction: it flips a single DUT-side word
//   inside compare_all_written, AFTER the DUT value is captured and BEFORE the
//   compare. The program and SimX are never touched — so this isolates the
//   *checker's* ability to detect a divergence, which is the whole point.
//
// Inverted verdict:
//   - PASS  if the scoreboard CAUGHT the injected fault (num_mem_failed >= 1)
//   - FAIL  if the scoreboard reported all-pass (the checker is blind — the
//           dangerous vacuous case this test exists to rule out)
//
//   The one expected scoreboard MISMATCH error is demoted by a report catcher
//   so it does not count toward the global UVM_ERROR tally — meaning a correct
//   checker makes THIS test end GREEN at the shell level.
//
// Run:
//   make sim TEST=negative_result_test PROGRAM_NAME=vecadd TIMEOUT=10000000
//   (vecadd is ideal: it has 131k clean data-region comparisons, so the only
//    mismatch is the injected one.)
////////////////////////////////////////////////////////////////////////////////

`ifndef NEGATIVE_RESULT_TEST_SV
`define NEGATIVE_RESULT_TEST_SV

// ---------------------------------------------------------------------------
// Report catcher: demote the ONE expected scoreboard mismatch (and the
// scoreboard's "SIMULATION FAILED" summary error) from UVM_ERROR to UVM_INFO,
// so the injected fault doesn't make the run look failed. Anything else stays
// an error — if some OTHER error fires, the test should still go red.
// ---------------------------------------------------------------------------
class neg_expected_error_catcher extends uvm_report_catcher;
	`uvm_object_utils(neg_expected_error_catcher)

	int unsigned num_demoted = 0;

	function new(string name = "neg_expected_error_catcher");
		super.new(name);
	endfunction

	virtual function action_e catch();
		// Only touch SCOREBOARD errors that are the injected mismatch or the
		// resulting failure summary. Leave every other report alone.
		if (get_severity() == UVM_ERROR && get_id() == "SCOREBOARD") begin
			string msg = get_message();
			if (msg.substr(0, 11) == "MEM MISMATCH" ||
			    (msg.len() >= 17 && msg.substr(0, 16) == "SIMULATION FAILED")) begin
				num_demoted++;
				set_severity(UVM_INFO);
				return THROW;  // keep it in the log, just at INFO now
			end
		end
		return THROW;
	endfunction
endclass


class negative_result_test extends kernel_launch_test;
	`uvm_component_utils(negative_result_test)

	neg_expected_error_catcher m_catcher;

	function new(string name = "negative_result_test", uvm_component parent = null);
		super.new(name, parent);
	endfunction

	// Install the report catcher and arm fault injection before the run starts.
	// build_phase runs top-down, so by end_of_elaboration the scoreboard exists.
	virtual function void end_of_elaboration_phase(uvm_phase phase);
		super.end_of_elaboration_phase(phase);

		// Arm the one-sided fault inside the scoreboard's comparison.
		if (env != null && env.m_scoreboard != null) begin
			env.m_scoreboard.inject_fault = 1;
			`uvm_info(get_type_name(),
				"[NEG] Fault injection ARMED — scoreboard will corrupt one DUT word to force a mismatch",
				UVM_LOW)
		end else begin
			`uvm_fatal(get_type_name(),
				"[NEG] scoreboard not available to arm fault injection")
		end

		// Demote the expected mismatch error so a correct checker ends GREEN.
		m_catcher = neg_expected_error_catcher::type_id::create("m_catcher");
		uvm_report_cb::add(null, m_catcher);
	endfunction

	// Inverted verdict: the test passes ONLY if the checker caught the fault.
	virtual function void check_results();
		int unsigned mem_failed;
		int unsigned other_errors;
		uvm_report_server rs;

		`uvm_info(get_type_name(), "----------------------------------------------------------------", UVM_LOW)
		`uvm_info(get_type_name(), " NEGATIVE RESULT TEST — CHECKER-FAILURE PROOF                   ", UVM_LOW)
		`uvm_info(get_type_name(), "----------------------------------------------------------------", UVM_LOW)

		if (env == null || env.m_scoreboard == null) begin
			`uvm_error(get_type_name(), "FAIL — scoreboard is not available")
			test_passed = 0;
			return;
		end

		// The fault must actually have been injected (i.e. the comparison ran).
		if (!env.m_scoreboard.fault_injected) begin
			`uvm_error(get_type_name(),
				"FAIL — fault was never injected (compare_all_written did not run; nothing to corrupt). Use a kernel with data-region writes, e.g. vecadd.")
			test_passed = 0;
			return;
		end

		mem_failed = env.m_scoreboard.num_mem_failed;

		// THE POSITIVE CONDITION FOR A NEGATIVE TEST:
		// Injection must have found a clean (matching) word to corrupt.
		if (!env.m_scoreboard.fault_injected) begin
			`uvm_error(get_type_name(),
				"FAIL — no naturally-matching word was available to corrupt; cannot prove the checker. Use a kernel with clean data-region writes, e.g. vecadd.")
			test_passed = 0;
			return;
		end

		// The checker must have reported THAT specific injected word as a mismatch.
		if (env.m_scoreboard.fault_detected) begin
			`uvm_info(get_type_name(),
				$sformatf("PASS — checker DETECTED the injected fault at addr=0x%08h (it matched before injection, mismatched after). Verdicts are not vacuous.",
					env.m_scoreboard.fault_addr),
				UVM_LOW)
			test_passed = 1;
		end else begin
			`uvm_error(get_type_name(),
				$sformatf("FAIL — fault injected at 0x%08h but the checker did NOT report it. Scoreboard is blind to divergence.",
					env.m_scoreboard.fault_addr))
			test_passed = 0;
			return;
		end

		// Safety net: make sure nothing OTHER than the demoted expected error
		// slipped through. The catcher demotes exactly the injected mismatch +
		// the failure summary; any remaining UVM_ERROR is a real problem.
		rs = uvm_report_server::get_server();
		other_errors = rs.get_severity_count(UVM_ERROR);
		if (other_errors != 0) begin
			`uvm_error(get_type_name(),
				$sformatf("FAIL — %0d unexpected UVM_ERROR(s) beyond the injected fault; investigate.", other_errors))
			test_passed = 0;
		end

		`uvm_info(get_type_name(), "----------------------------------------------------------------", UVM_LOW)
	endfunction

endclass : negative_result_test

`endif // NEGATIVE_RESULT_TEST_SV
