////////////////////////////////////////////////////////////////////////////////
// File: negative_dropped_store_test.sv
// Description: Negative test for the BIDIRECTIONAL (SB-DIR) scoreboard check.
//
// Purpose:
//   Proves the scoreboard detects a DROPPED STORE — a memory word SimX wrote
//   that the DUT never did (silent data loss). This is the OTHER direction from
//   negative_result_test's bit-flip: the flip proves the checker catches WRONG
//   values (forward pass, over DUT-written words); this proves it catches
//   MISSING values (reverse pass, over words the DUT never wrote).
//
//   The drop is ONE-SIDED and injected inside the scoreboard: one genuine DUT
//   output word is removed from the shadow AND the DUT's real memory (mem_model)
//   at that address is reset to its load value, so it looks exactly like a store
//   the DUT never performed. The program and SimX are never touched. A purely
//   one-directional checker (forward pass only) would report all-pass here — the
//   dangerous blind spot this test exists to rule out.
//
// Inverted verdict:
//   - PASS  if the scoreboard CAUGHT the dropped store (reverse pass flagged it)
//   - FAIL  if the scoreboard reported all-pass (checker is blind to data loss)
//
// Run:
//   make sim TEST=negative_dropped_store_test PROGRAM_NAME=vecadd_lite TIMEOUT=200000
//   (any kernel with clean non-zero data-region output works; vecadd_lite is ideal.)
////////////////////////////////////////////////////////////////////////////////

`ifndef NEGATIVE_DROPPED_STORE_TEST_SV
`define NEGATIVE_DROPPED_STORE_TEST_SV

// Demote the ONE expected "DROPPED STORE" error (and the failure summary) so the
// injected drop doesn't make the run look failed; anything else stays a real error.
class neg_drop_error_catcher extends uvm_report_catcher;
	`uvm_object_utils(neg_drop_error_catcher)

	int unsigned num_demoted = 0;

	function new(string name = "neg_drop_error_catcher");
		super.new(name);
	endfunction

	virtual function action_e catch();
		if (get_severity() == UVM_ERROR && get_id() == "SCOREBOARD") begin
			string msg = get_message();
			if ((msg.len() >= 13 && msg.substr(0, 12) == "DROPPED STORE") ||
			    (msg.len() >= 17 && msg.substr(0, 16) == "SIMULATION FAILED")) begin
				num_demoted++;
				set_severity(UVM_INFO);
				return THROW;
			end
		end
		return THROW;
	endfunction
endclass


class negative_dropped_store_test extends kernel_launch_test;
	`uvm_component_utils(negative_dropped_store_test)

	neg_drop_error_catcher m_catcher;

	function new(string name = "negative_dropped_store_test", uvm_component parent = null);
		super.new(name, parent);
	endfunction

	virtual function void end_of_elaboration_phase(uvm_phase phase);
		super.end_of_elaboration_phase(phase);

		if (env != null && env.m_scoreboard != null) begin
			env.m_scoreboard.drop_store = 1;
			`uvm_info(get_type_name(),
				"[NEG-DROP] Dropped-store injection ARMED — scoreboard will remove one DUT output word",
				UVM_LOW)
		end else begin
			`uvm_fatal(get_type_name(),
				"[NEG-DROP] scoreboard not available to arm dropped-store injection")
		end

		m_catcher = neg_drop_error_catcher::type_id::create("m_catcher");
		uvm_report_cb::add(null, m_catcher);
	endfunction

	// Inverted verdict: passes ONLY if the reverse pass caught the dropped store.
	virtual function void check_results();
		int unsigned other_errors;
		uvm_report_server rs;

		`uvm_info(get_type_name(), "----------------------------------------------------------------", UVM_LOW)
		`uvm_info(get_type_name(), " NEGATIVE DROPPED-STORE TEST — BIDIRECTIONAL CHECKER PROOF      ", UVM_LOW)
		`uvm_info(get_type_name(), "----------------------------------------------------------------", UVM_LOW)

		if (env == null || env.m_scoreboard == null) begin
			`uvm_error(get_type_name(), "FAIL — scoreboard is not available")
			test_passed = 0;
			return;
		end

		// The drop must actually have happened (a matching non-zero word existed).
		if (!env.m_scoreboard.store_dropped) begin
			`uvm_error(get_type_name(),
				"FAIL — no store was dropped (no clean non-zero output word to remove, or mem_model absent). Use a kernel with non-zero data-region output, e.g. vecadd_lite.")
			test_passed = 0;
			return;
		end

		// The reverse pass must have reported that specific dropped store.
		if (env.m_scoreboard.drop_detected) begin
			`uvm_info(get_type_name(),
				$sformatf("PASS — checker DETECTED the dropped store at addr=0x%08h via the reverse pass (SimX wrote it, DUT did not). Bidirectional check works; forward-only would have been blind.",
					env.m_scoreboard.drop_addr),
				UVM_LOW)
			test_passed = 1;
		end else begin
			`uvm_error(get_type_name(),
				$sformatf("FAIL — store dropped at 0x%08h but the checker did NOT report it. Scoreboard is blind to dropped stores (one-directional).",
					env.m_scoreboard.drop_addr))
			test_passed = 0;
			return;
		end

		// Safety net: only the demoted DROPPED STORE (+ summary) may be present.
		rs = uvm_report_server::get_server();
		other_errors = rs.get_severity_count(UVM_ERROR);
		if (other_errors != 0) begin
			`uvm_error(get_type_name(),
				$sformatf("FAIL — %0d unexpected UVM_ERROR(s) beyond the injected drop; investigate.", other_errors))
			test_passed = 0;
		end

		`uvm_info(get_type_name(), "----------------------------------------------------------------", UVM_LOW)
	endfunction

endclass : negative_dropped_store_test

`endif // NEGATIVE_DROPPED_STORE_TEST_SV
