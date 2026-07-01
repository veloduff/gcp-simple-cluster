#!/usr/bin/env python3
import sys
import re

# Regex to match the unixy play header:
# e.g.: "- 1. Setup Environment Facts & Prerequisites on hosts: all_nodes -"
play_header_re = re.compile(r'^-\s+(\d+)\.\s+(.*?)\s+on hosts:\s+\S+\s+-$')
# Regex to match the play recap header:
recap_header_re = re.compile(r'^-\s+Play recap\s+-$')

current_play_num = None
current_play_name = None
has_tasks = False
buffered_header = None

def flush_play():
    global buffered_header, has_tasks
    if buffered_header:
        if not has_tasks:
            # Nothing was done in this play
            print(f"{current_play_num}. {current_play_name}: option not selected at launch", flush=True)
        buffered_header = None

for line in sys.stdin:
    line = line.rstrip('\n')
    
    # Match play header
    play_match = play_header_re.match(line)
    if play_match:
        flush_play()
        current_play_num = play_match.group(1)
        current_play_name = play_match.group(2)
        buffered_header = line
        has_tasks = False
        continue
        
    # Match play recap header
    recap_match = recap_header_re.match(line)
    if recap_match:
        flush_play()
        print("Play recap", flush=True)
        continue

    # Skip empty lines to keep output compact and clean
    if line.strip() == "":
        continue

    # If we have a buffered header, it means we are receiving task output for the current play
    if buffered_header:
        if not has_tasks:
            # Print the header (without the hyphens)
            print(f"{current_play_num}. {current_play_name}", flush=True)
            has_tasks = True
            
    print(line, flush=True)

# Flush any remaining play at the end
flush_play()
