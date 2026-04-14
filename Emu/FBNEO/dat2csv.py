#!/usr/bin/env python3

"""
Script to convert the fbneo .dat to a minimal .csv for faster reading.
.dat source: https://github.com/libretro/FBNeo/blob/master/dats/FinalBurn%20Neo%20(ClrMame%20Pro%20XML%2C%20Arcade%20only).dat
"""

import os
import re
import csv
import argparse
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser(prog='dat2csv', description='Convert FBNeo .dat to a minimal .csv')
parser.add_argument('filename')
args = parser.parse_args()

tree = ET.parse(args.filename)
root = tree.getroot()

if root.tag != "datafile":
    print("Invalid file.")
    os.exit(1)

with open('fbneo.csv', 'w', newline='') as csvfile:
    writer = csv.writer(csvfile)

    for game in root.iter('game'):
        name = game.attrib["name"]
        desc = game.find('description').text

        pattern = r'\(.*?\)'
        desc = re.sub(pattern, '', desc) # cleanup name

        writer.writerow([f"{name}.zip", desc.strip()])
