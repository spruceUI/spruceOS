#!/usr/bin/env python3

"""
Script to convert the output of scummvm --list-games in a .txt file to .csv for faster reading.
"""

import csv
import argparse

parser = argparse.ArgumentParser(prog='list2csv', description='Convert SCUMMVM game list txt to a minimal .csv')
parser.add_argument('filename')
args = parser.parse_args()

with open(args.filename, newline='') as txtfile:
    with open('scummvm.csv', 'w', newline='') as csvfile:
        writer = csv.writer(csvfile)

        # Skip first line
        txtfile.readline()

        for line in txtfile:
            if ":" in line:
                idx1 = line.find(":")
                idx2 = line.find(" ")

                gid = line[idx1+1:idx2]
                name = line[idx2:].strip()

                writer.writerow([gid, name])
