
CFLAGS = -g -Wall
LIBS =
BINDIR = /usr/local/bin
SCRIPTNAME=/etc/init.d/RC

all: RC

RC: RC.c
	gcc -o RC $(CFLAGS) RC.c $(LIBS)

install: RC
	mkdir -p $(BINDIR)
	install -m 755 RC $(BINDIR)
	cp RC.init $(SCRIPTNAME)
	update-rc.d RC defaults
	service RC start

clean:
	rm -f RC
	
