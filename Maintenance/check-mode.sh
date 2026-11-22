grep -qw persistence-read-only /proc/cmdline && echo "READ-ONLY mode" || echo "PERSISTENT mode";

findmnt -no OPTIONS / | grep -oE '(lower|upper)dir=[^,]*';
