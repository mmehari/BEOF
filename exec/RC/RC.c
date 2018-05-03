
// HEADER DEFINITION
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/time.h>
#include <sys/stat.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <signal.h>
#include <syslog.h>
#include <errno.h>
#include <fcntl.h>
#include <pwd.h>

// MACRO DEFINITION
#define BOLD   "\033[1m\033[30m"
#define RESET   "\033[0m"

/* Message structure */
typedef struct message
{
	char type;
	uint16_t seq;
	char body[1280];
} message_t;

int lfp = -1;
char *lock_file = NULL;

// For the given IP address, retrieve interface name
char* IPtoIF(char *ip_addr)
{
	struct ifaddrs *addrs, *iap;
	struct sockaddr_in *sa;
	char buf[32];

	getifaddrs(&addrs);
	for (iap = addrs; iap != NULL; iap = iap->ifa_next)
	{
		if (iap->ifa_addr && (iap->ifa_flags & IFF_UP) && iap->ifa_addr->sa_family == AF_INET)
		{
			sa = (struct sockaddr_in *)(iap->ifa_addr);
			inet_ntop(iap->ifa_addr->sa_family, (void *)&(sa->sin_addr), buf, sizeof(buf));
			if (strcmp(ip_addr, buf) == 0)
				break;
		}
	}
	freeifaddrs(addrs);

	return iap->ifa_name;
}
 
// This will start the client resource controller
int startRC(char *host_RC, uint16_t port_RC, char *group, char *logFile)
{
	int socket_desc, reuse = 1;
	struct sockaddr_in addr_RC, addr_EC;
	struct ip_mreq addr_group;

	uint16_t previous_seq = 0;
	message_t recv_message, send_message;
	socklen_t len = sizeof(struct sockaddr_in);

	char message[2560], query[2560];

	FILE *qp;

	// Log starting time of RC
	sprintf(message,"echo \"<START_RC at=\\\"`date +%%s.%%N`\\\" />\" > %s", logFile);
	system(message);

	// Create a datagram socket
	socket_desc = socket(AF_INET, SOCK_DGRAM, 0);
	if (socket_desc < 0)
	{
		sprintf(message,"echo \"<ERROR_MSG id=\\\"0\\\" at=\\\"`date +%%s.%%N`\\\" msg=\\\"SOCK_DGRAM: %s\\\" />\" >> %s", strerror(errno), logFile);
		system(message);

		return -1;
	}

	// Enable SO_REUSEADDR to allow multiple instances of this application to receive copies of the multicast datagrams
	if (setsockopt(socket_desc, SOL_SOCKET, SO_REUSEADDR,(char *)&reuse, sizeof(reuse)) < 0)
	{
		sprintf(message,"echo \"<ERROR_MSG id=\\\"0\\\" at=\\\"`date +%%s.%%N`\\\" msg=\\\"SO_REUSEADDR: %s\\\" />\" >> %s", strerror(errno), logFile);
		system(message);

		return -1;
	}

	// Bind to the proper port number and ANY IP address.
	memset(&addr_RC, 0, sizeof(struct sockaddr_in));
	addr_RC.sin_family = AF_INET;
	addr_RC.sin_port = htons(port_RC);
	addr_RC.sin_addr.s_addr  = INADDR_ANY;	// Bind to any address since we expect multicast packets
	if (bind(socket_desc, (struct sockaddr*)&addr_RC, sizeof(struct sockaddr_in)))
	{
		sprintf(message,"echo \"<ERROR_MSG id=\\\"0\\\" at=\\\"`date +%%s.%%N`\\\" msg=\\\"BIND: %s\\\" />\" >> %s", strerror(errno), logFile);
		system(message);

		return -1;
	}

	// Join the multicast groups
	strtok(group,",");
	while(group != NULL)
	{
		addr_group.imr_multiaddr.s_addr = inet_addr(group);
		addr_group.imr_interface.s_addr = inet_addr(host_RC);

		if (setsockopt(socket_desc, IPPROTO_IP, IP_ADD_MEMBERSHIP, (char *)&addr_group, sizeof(struct ip_mreq)) < 0)
		{
			sprintf(message,"echo \"<ERROR_MSG id=\\\"0\\\" at=\\\"`date +%%s.%%N`\\\" msg=\\\"IP_ADD_MEMBERSHIP: %s\\\" />\" >> %s", strerror(errno), logFile);
			system(message);

			return -1;
		}
		group = strtok(NULL,",");
	};

	while(1)
	{
		// Read from the socket
		if(recvfrom(socket_desc, &recv_message, sizeof(message_t), 0, (struct sockaddr *)&addr_EC, (socklen_t *)&len) < 0)
		{
			sprintf(message,"echo \"<ERROR_MSG id=\\\"%u\\\" at=\\\"`date +%%s.%%N`\\\" msg=\\\"RECVFROM: %s\\\" />\" >> %s", previous_seq, strerror(errno), logFile);
			system(message);
		}		

		// Only process new messages
		if(recv_message.seq > previous_seq)
		{
			// EC expects result
			if(recv_message.type == 'x')
			{
				// PING request. Reply PONG
				if(strcmp(recv_message.body, "PING") == 0)
				{
					send_message.type = 'r';
					send_message.seq = recv_message.seq;
					sprintf(send_message.body,"PONG\nEOR");
					if(sendto(socket_desc, &send_message, strlen(send_message.body) + 5, 0, (struct sockaddr *)&addr_EC, sizeof(struct sockaddr_in)) < 0)
					{
						sprintf(message,"echo \"<ERROR_MSG id=\\\"%u\\\" at=\\\"`date +%%s.%%N`\\\" msg=\\\"SENDTO: %s\\\" />\" >> %s", recv_message.seq, strerror(errno), logFile);
						system(message);
					}
				}
				// Control interface request
				else if(strcmp(recv_message.body, "CTRL_IF") == 0)
				{
					send_message.type = 'r';
					send_message.seq = recv_message.seq;
					sprintf(send_message.body,"%s\nEOR", IPtoIF(host_RC));
					if(sendto(socket_desc, &send_message, strlen(send_message.body) + 5, 0, (struct sockaddr *)&addr_EC, sizeof(struct sockaddr_in)) < 0)
					{
						sprintf(message,"echo \"<ERROR_MSG id=\\\"%u\\\" at=\\\"`date +%%s.%%N`\\\" msg=\\\"SENDTO: %s\\\" />\" >> %s", recv_message.seq, strerror(errno), logFile);
						system(message);
					}
				}
				// EXIT request. Close RC session
				else if(strcmp(recv_message.body, "EXIT") == 0)
				{
					send_message.type = 'r';
					send_message.seq = recv_message.seq;
					sprintf(send_message.body,"EOR");
					if(sendto(socket_desc, &send_message, strlen(send_message.body) + 5, 0, (struct sockaddr *)&addr_EC, sizeof(struct sockaddr_in)) < 0)
					{
						sprintf(message,"echo \"<ERROR_MSG id=\\\"%u\\\" at=\\\"`date +%%s.%%N`\\\" msg=\\\"SENDTO: %s\\\" />\" >> %s", recv_message.seq, strerror(errno), logFile);
						system(message);
					}

					// Log end of message
					sprintf(message,"echo \"<END_MSG id=\\\"%u\\\" at=\\\"`date +%%s.%%N`\\\" />\" >> %s", recv_message.seq, logFile);
					system(message);

					// Log end of RC
					sprintf(message,"echo \"<END_RC at=\\\"`date +%%s.%%N`\\\" />\" >> %s", logFile);
					system(message);

					// break while loop
					break;
				}
				// Else, execute command message
				else
				{
					// Format the message to annotate stderr messages by system time
					sprintf(query,"bash -c '%s 2> >(tr \"\\n\" \"\\r\" | tr \"\\\"\" \"\'\\\'\'\" | xargs -0 -r | while read MSG; do echo \"<ERROR_MSG id=\\\"%u\\\" at=\\\"`date +%%s.%%N`\\\" msg=\\\"$MSG\\\" />\" >> %s; done) &'", recv_message.body, recv_message.seq, logFile);

					// Execute query
					qp = popen(query, "r");

					if(qp != NULL)
					{
						send_message.type = 'r';
						send_message.seq = recv_message.seq;

						while (fgets(send_message.body, 1280, qp))
						{
							// send result data back to EC
							if(sendto(socket_desc, &send_message, strlen(send_message.body) + 5, 0, (struct sockaddr *)&addr_EC, sizeof(struct sockaddr_in)) < 0)
							{
								sprintf(message,"echo \"<ERROR_MSG id=\\\"%u\\\" at=\\\"`date +%%s.%%N`\\\" msg=\\\"SENDTO: %s\\\" />\" >> %s", recv_message.seq, strerror(errno), logFile);
								system(message);
							}
						}

						// Send End Of Result (EOR) message to EC
						sprintf(send_message.body,"EOR");
						if(sendto(socket_desc, &send_message, strlen(send_message.body) + 5, 0, (struct sockaddr *)&addr_EC, sizeof(struct sockaddr_in)) < 0)
						{
							sprintf(message,"echo \"<ERROR_MSG id=\\\"%u\\\" at=\\\"`date +%%s.%%N`\\\" msg=\\\"SENDTO: %s\\\" />\" >> %s", recv_message.seq, strerror(errno), logFile);
							system(message);
						}

						// Close query pointer
						pclose(qp);
					}
				}
			}
			// EC does not expect result
			else if(recv_message.type == 'X')
			{
				// Execute recieved message using bourn again shell (bash)
				sprintf(query,"bash -c '%s 2> >(tr \"\\n\" \"\\r\" | tr \"\\\"\" \"\'\\\'\'\" | xargs -0 -r | while read MSG; do echo \"<ERROR_MSG id=\\\"%u\\\" at=\\\"`date +%%s.%%N`\\\" msg=\\\"$MSG\\\" />\" >> %s; done) &'", recv_message.body, recv_message.seq, logFile);
				system(query);
				usleep(50000);
			}

			// Log end of message
			sprintf(message,"echo \"<END_MSG id=\\\"%u\\\" at=\\\"`date +%%s.%%N`\\\" />\" >> %s", recv_message.seq, logFile);
			system(message);
		}

		// Adjust previous sequence number to avoid duplicate packet processing
		previous_seq = recv_message.seq;
	}

	// Exit quietly
	return 0;	
}

// Daemonize the program
static void daemonize()
{
	pid_t pid;
	char str[256];

	/* Fork off the parent process */
	pid = fork();
	if (pid < 0)
	{
		syslog(LOG_ERR, "First FORK@daemonize error: %s", strerror(errno));
		exit(EXIT_FAILURE);
	}
	/* Success: Let the parent terminate */
	if(pid > 0)
	{
		exit(EXIT_SUCCESS);
	}

	/* Create a new SID for the child process */
	if (setsid() < 0)
	{
		syslog(LOG_ERR, "SETSID@daemonize error: %s", strerror(errno));
		exit(EXIT_FAILURE);
	}

	/* Ignore signal sent from child to parent process */
	signal(SIGCHLD, SIG_IGN);

	/* Fork off for the second time*/
	pid = fork();

	/* An error occurred */
	if(pid < 0)
	{
		syslog(LOG_ERR, "Second FORK@daemonize error: %s", strerror(errno));
		exit(EXIT_FAILURE);
	}

	/* Success: Let the parent terminate */
	if(pid > 0)
	{
		exit(EXIT_SUCCESS);
	}

	/* Set new file permissions */
	umask(0);

	/* Change the current working directory.  This prevents the current
	   directory from being locked; hence not being able to remove it. */
	if ((chdir("/")) < 0)
	{
		syslog(LOG_ERR, "CHDIR@daemonize error: %s", strerror(errno));
		exit(EXIT_FAILURE);
	}

	/* Create a lock file */
	lfp = open(lock_file, O_RDWR|O_CREAT, 0640);

	/* Can't open lockfile */
	if (lfp < 0)
	{
		syslog(LOG_ERR, "OPEN@daemonize error: %s", strerror(errno));
		exit(EXIT_FAILURE);
	}

	/* Can't lock file */
	if(lockf(lfp, F_TLOCK, 0) < 0)
	{
		syslog(LOG_ERR, "LOCKF@daemonize error: %s", strerror(errno));
		exit(EXIT_FAILURE);
	}

	/* Get current PID */
	sprintf(str, "%d\n", getpid());

	/* Write PID to lockfile */
	write(lfp, str, strlen(str));

	/* Redirect standard files to /dev/null */
	freopen("/dev/null", "r", stdin);
	freopen("/dev/null", "w", stdout);
	freopen("/dev/null", "w", stderr);
}

/* Callback function for handling signals */
void cleanup(int sig)
{
	syslog(LOG_INFO, "stopping RC daemon");

	/* Unlock and close lockfile */
	if(lfp != -1)
	{
		if(lockf(lfp, F_ULOCK, 0) < 0)
		{
			syslog(LOG_ERR, "LOCKF@cleanup error: %s", strerror(errno));
			exit(EXIT_FAILURE);
		}
		close(lfp);
	}

	/* Try to delete lockfile */
	if(lock_file != NULL)
	{
		unlink(lock_file);
	}

	exit(EXIT_SUCCESS);
}

int main (int argc, char *argv[])
{
	uint16_t port_RC_CONNECT = 12345;

	int option = -1;
	while ((option = getopt (argc, argv, "hp:l:")) != -1)
	{
	    switch (option)
	    {
			case 'h':
				fprintf(stderr, "Description\n");
				fprintf(stderr, "-----------\n");
				fprintf(stderr, BOLD "proxy_RC" RESET " is a server program that acts as a proxy Resource Controller (RC)\n");
				fprintf(stderr, "It accepts commands from a client Experiment Controller (EC) and execute them locally.\n");
				fprintf(stderr, "The executed commands either return or do not return result back.\n\n");
				fprintf(stderr, "Argument list\n");
				fprintf(stderr, "-------------\n");
				fprintf(stderr, "-h\t\t\thelp menu\n");
				fprintf(stderr, "-p port_RC_CONNECT\t\tResource controller stream socket port number [eg. -p 8800]\n");
				fprintf(stderr, "-l lock_file\t\tLock file used by daemonized program [eg. -l /var/run/RC.pid]\n\n");
				return 1;
			case 'p':
				port_RC_CONNECT = atoi(optarg);
				break;
			case 'l':
				lock_file = strdup(optarg);
				break;
			default:
				fprintf(stderr, "RC: missing operand. Type './RC -h' for more information.\n");
				exit(1);
	    }
	}

	int streamFd, reuse=1, clientFd;
	struct sockaddr_in addr_RC, addr_EC;
	socklen_t sockLen;

	// Make sure lock_file is not empty
	if(lock_file == NULL)
		lock_file = strdup("/var/run/RC.pid");

	/* Open system log and write message to it */
	openlog("RC", LOG_PID|LOG_CONS, LOG_DAEMON);
	syslog(LOG_INFO, "starting RC Daemon");

	// Create a stream socket
	streamFd = socket(AF_INET, SOCK_STREAM, 0);
	if(streamFd < 0)
	{
		syslog(LOG_ERR, "SOCK_STREAM@main error: %s", strerror(errno));
		exit(EXIT_FAILURE);
	}
	// Enable SO_REUSEADDR to allow multiple instances of this application to receive copies of the multicast datagrams
	if(setsockopt(streamFd, SOL_SOCKET, SO_REUSEADDR,(char *)&reuse, sizeof(reuse)) < 0)
	{
		syslog(LOG_ERR, "SO_REUSEADDR@main error: %s", strerror(errno));
		exit(EXIT_FAILURE);
	}

	// Bind to the RC port number and ANY IP address.
	memset(&addr_RC, 0, sizeof(struct sockaddr_in));
	addr_RC.sin_family = AF_INET;
	addr_RC.sin_port = htons(port_RC_CONNECT);
	addr_RC.sin_addr.s_addr  = INADDR_ANY;	// Bind to any address since we expect multicast packets
	if(bind(streamFd, (struct sockaddr*)&addr_RC, sizeof(struct sockaddr_in)))
	{
		syslog(LOG_ERR, "BIND@main error: %s", strerror(errno));
		exit(EXIT_FAILURE);
	}

	// Listen maximum socket connections
	if(listen(streamFd, SOMAXCONN))
	{
		syslog(LOG_ERR, "LISTEN@main error: %s", strerror(errno));
		exit(EXIT_FAILURE);
	}

	// Deamonize this program
	daemonize();
	
	/* Daemon will handle two signals */
	signal(SIGINT,  cleanup);
	signal(SIGTERM, cleanup);

	// accept connection from a client
	sockLen = sizeof(struct sockaddr_in);
	while( (clientFd = accept(streamFd, (struct sockaddr *)&addr_EC, &sockLen)) )
	{
		// Create a new child process
		int pid = fork();

		// parent process
		if(pid > 0)
		{
			// Ignore SIGCHLD signal
			signal(SIGCHLD, SIG_IGN);

			// continue to accept new connections
			continue;
		}
		// child process
		else if(pid == 0)
		{
		   	// Exit loop and become a Resource Controller (RC)
			break;
		}
		else
		{
			syslog(LOG_ERR, "FORK@main error: %s", strerror(errno));
			exit(EXIT_FAILURE);
		}
	}

	int recv_size;
	message_t recv_message, send_message;

	char *host_RC = NULL;
	uint16_t port_RC = 0;
	char *logFile = NULL;
	char *group = NULL;

	// Receive EC specification from the STREAM socket and create a new DGRAM socket
	if((recv_size = recv(clientFd , &recv_message , sizeof(recv_message) , 0)) < 0)
	{
		syslog(LOG_ERR, "RECV@main error: %s", strerror(errno));
		exit(EXIT_FAILURE);
	}

	// Parse RC specification
	host_RC = strtok(recv_message.body, " ");
	port_RC = atoi(strtok(NULL, " "));
	logFile = strtok(NULL, " ");
	group   = strtok(NULL, " ");

	// Make sure EC specification is complete
	if(host_RC == NULL || port_RC == 0 || logFile == NULL)
	{
		send_message.type = 'r';
		send_message.seq = recv_message.seq;
		sprintf(send_message.body,"Incomplete EC specification\nEOR");
		if(send(clientFd, &send_message, strlen(send_message.body) + 5, 0) < 0)
		{
			syslog(LOG_ERR, "SEND@main error: %s", strerror(errno));
		}
		exit(EXIT_FAILURE);
	}

	// At this point, everything is complete from the EC side and we send a positive response
	send_message.type = 'r';
	send_message.seq = recv_message.seq;
	sprintf(send_message.body,"%s %u %s %s\nEOR", host_RC, port_RC, logFile, group);
	if(send(clientFd, &send_message, strlen(send_message.body) + 5, 0) < 0)
	{
		syslog(LOG_ERR, "SEND@main error: %s", strerror(errno));
		exit(EXIT_FAILURE);
	}

	// close client connection
	close(clientFd);

	// Start resource controller
	startRC(host_RC, port_RC, group, logFile);

	return 0;
}
