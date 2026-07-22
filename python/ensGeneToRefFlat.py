#!/usr/bin/env python3

# Quick and dirty script to convert a "knownGene" format file into refFlat format.
#
# Not quite simple enough to do in the shell, because we need to conditionally
# include one column if it is non-blank, otherwise a different column


# decision: GENE_ID_COL will be field 13 name2, or field 2 name.

import sys

GENE_ID_COL = 12 # 'name2', eg FBgn0031208
TRANSCRIPT_ID_COL = 1 # 'name' eg FBtr0300690

count = 0
for line in sys.stdin:
  flds = line.strip().split("\t")
  if len(flds) != 16:
    sys.stderr.write("Bug: %d columns in line".format(count,))
    sys.exit(-1)
    # if GENE_ID_COL field is empty,
    # then 'tag' takes value from GENE_ID_COL field
    # else 'tag' takes value from GENE_ID_COL field
  if flds[GENE_ID_COL] == "":
    tag = flds[TRANSCRIPT_ID_COL]
  else:
    tag = flds[GENE_ID_COL]
    # write row out:
    #print("Length of array:", len(flds))
    flds.pop(11)
    #print("Length of array:", len(flds))
    flds.pop(0)
    #print("Length of array:", len(flds))
  sys.stdout.write("%s\t%s\n".format(tag,"\t".join(flds[0:10])))
  count += 1
sys.stderr.write("translated %d lines\n".format(count,))
