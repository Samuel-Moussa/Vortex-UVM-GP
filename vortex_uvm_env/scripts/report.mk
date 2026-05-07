report: simulate
	@echo -e "${CYAN}================================================================================${NC}"
	@echo -e "${CYAN}Results${NC}"
	@echo -e "${CYAN}================================================================================${NC}"
	@LOG_FILE="$(RUN_DIR)/logs/simulation.log"; \
	SUMMARY_FILE="$(RUN_DIR)/reports/SUMMARY.txt"; \
	UVM_ERRORS=$$(grep -c "^# UVM_ERROR /" "$$LOG_FILE" || true); \
	UVM_FATALS=$$(grep -c "^# UVM_FATAL /" "$$LOG_FILE" || true); \
	RTL_ERRORS=$$(grep -c "RTL ERROR" "$$LOG_FILE" || true); \
	if grep -q "TEST PASSED\|SMOKE TEST PASSED" "$$LOG_FILE"; then \
		echo -e "${GREEN}✓ TEST PASSED ✓  ($$UVM_ERRORS UVM errors, $$RTL_ERRORS RTL errors)${NC}"; \
		STATUS="PASSED"; EXIT_CODE=0; \
	else \
		echo -e "${RED}✗ TEST FAILED ✗  ($$UVM_ERRORS UVM errors, $$UVM_FATALS Fatals)${NC}"; \
		STATUS="FAILED"; EXIT_CODE=1; \
	fi; \
	echo "Status: $$STATUS" >> "$$SUMMARY_FILE"; \
	if grep -q "Total Cycles\|Cycles:" "$$LOG_FILE"; then \
		echo ""; echo -e "${BLUE}ℹ Statistics:${NC}"; \
		grep -E "Total Cycles|Cycles:|Instructions|IPC" "$$LOG_FILE" | sed 's/^/  /' | tee -a "$$SUMMARY_FILE"; \
	fi; \
	echo -e "${CYAN}================================================================================${NC}"; \
	echo -e "${CYAN}Summary${NC}"; \
	echo -e "${CYAN}================================================================================${NC}"; \
	if [ "$$EXIT_CODE" -eq 0 ]; then echo -e "${GREEN}✓ TEST PASSED ✓${NC}\n"; else echo -e "${RED}✗ TEST FAILED ✗${NC}\n"; fi; \
	echo "Test:      $(TEST)"; \
	echo "Program:   $(PROGRAM)"; \
	echo "Status:    $$STATUS"; \
	echo ""; echo "Files:"; \
	echo "  Run Dir:   $(RUN_DIR)"; \
	echo "  Log:       logs/simulation.log"; \
	echo "  Waveform:  waves/$(TEST)_$(INTERFACE).vcd"; \
	echo "  Summary:   reports/SUMMARY.txt"; \
	echo "  Config:    reports/config.txt"; \
	echo ""; echo "Quick access:"; \
	echo "  cd results/latest"; \
	echo "  cat reports/SUMMARY.txt"; \
	echo "  vsim -view waves/*.vcd"; \
	echo ""; \
	if [ "$$EXIT_CODE" -eq 0 ]; then echo -e "${GREEN}✓ All done! ✓${NC}"; fi; \
	exit $$EXIT_CODE