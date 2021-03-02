#!/usr/bin/env -S awk -f

$2~/Atom/ {
	atom[atomlen++] = $1
}

$2~/RSS/ {
	rss[rsslen++] = $1
}

{
	other[otherlen++] = $1
}

function print_array(a) {
	for (i in a)
		print a[i];
}

END {
	if (atomlen) {
		print_array(atom);
	} else if (rsslen) {
		print_array(rss);
	} else {
		print_array(other);
	}
}

