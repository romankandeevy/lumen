import re, sys
p = sys.argv[1] + "/dates.py"
s = open(p).read()
s = s.replace("    return year % 4 == 0", "    return year % 4 == 0 and (year % 100 != 0 or year % 400 == 0)")
s = s.replace("        m, d, y = text.split(\".\")", "        d, m, y = text.split(\".\")")
open(p, "w").write(s)
