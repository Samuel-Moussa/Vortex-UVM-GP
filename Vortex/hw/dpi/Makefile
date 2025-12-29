# Vortex DPI Library Makefile (Fixed for C++17)

VERILATOR_ROOT ?= $(HOME)/verilator
VERILATOR_INC = $(VERILATOR_ROOT)/include
VORTEX_BUILD = $(HOME)/Vortex_UVM_GP/Vortex/build/hw
VORTEX_SIM = $(HOME)/Vortex_UVM_GP/Vortex/sim/common

CXX = g++
CXXFLAGS = -fPIC -O2 -std=c++17 \
           -I$(VERILATOR_INC) \
           -I$(VERILATOR_INC)/vltstd \
           -I$(VORTEX_BUILD) \
           -I$(VORTEX_SIM)

SOURCES = float_dpi.cpp util_dpi.cpp
OBJECTS = $(SOURCES:.cpp=.o)
TARGET = libdpi.so

all: $(TARGET)

$(TARGET): $(OBJECTS)
	$(CXX) -shared -o $@ $(OBJECTS)
	@echo "✓ DPI library: $(TARGET)"

%.o: %.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

clean:
	rm -f $(OBJECTS) $(TARGET)

.PHONY: all clean
