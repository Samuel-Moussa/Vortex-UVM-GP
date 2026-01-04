# Read the reversed instruction file
file_path = "formatted_hex.txt"  # Update with your file path

# Read the file contents
with open(file_path, "r") as file:
    lines = file.readlines()

# Process each line: split into 16 instructions, reverse, and join back
corrected_lines = []
for line in lines:
    line = line.strip()  # Remove newline and spaces
    if len(line) == 128:  # Ensure it's a full 16-instruction line
        instructions = [line[i:i+8] for i in range(0, 128, 8)]  # Split into 8-char instructions
        reversed_line = "".join(reversed(instructions))  # Reverse order
        corrected_lines.append(reversed_line)

# Save the corrected instructions to a new file
corrected_file_path = "kernel.txt"  # Change as needed
with open(corrected_file_path, "w") as file:
    file.write("\n".join(corrected_lines))

print("Corrected file saved as:", corrected_file_path)