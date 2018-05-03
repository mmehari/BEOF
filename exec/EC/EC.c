
#include <stdio.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <arpa/inet.h>
#include <stdlib.h>
#include <unistd.h>
#include <time.h>
#include <errno.h>

#include "uthash.h"	// hashing function header file


// MACRO DEFINITION

#define BOLD   "\033[1m\033[30m"
#define RESET   "\033[0m"

struct RECORD_t
{
	char		result_IPs[16];		// IP address from result sending RC
	UT_hash_handle	hh;			// hash function handler
};

/* Message structure */
typedef struct message
{
	char type;
	uint16_t seq;
	char body[1280];
} message_t;


int main (int argc, char *argv[])
{
	int create_RC = 0;
	char *host_EC = NULL;
	uint16_t port_EC = 0;
	char *host_RC = NULL;
	uint16_t port_RC = 0;
	message_t *send_message = NULL;
	char *result_IPs = NULL;
	uint8_t RC_count = 1;
	uint8_t recv_sock_timeout = 5;

	int option = -1;
	while ((option = getopt (argc, argv, "hcn:p:m:q:x:X:r:t:")) != -1)
	{
	    switch (option)
	    {
			case 'h':
				fprintf(stderr, "Description\n");
				fprintf(stderr, "-----------\n");
				fprintf(stderr, BOLD "proxy_EC" RESET " is a client application that acts as a proxy Experiment Controller (EC)\n");
				fprintf(stderr, "It sends commands to a resource controller socket specified by [hostname:port] and gets the result or ACK back.\n");
				fprintf(stderr, "Argument list\n");
				fprintf(stderr, "-------------\n");
				fprintf(stderr, "-h\t\t\thelp menu\n");
				fprintf(stderr, "-c\t\t\tcreate a resource controller\n");
				fprintf(stderr, "-n host_EC\t\tLocal host name [eg. -n 192.168.10.1]\n");
				fprintf(stderr, "-p port_EC\t\tLocal port number [eg. -p 8000]\n");
				fprintf(stderr, "-m host_RC\t\tResource controller host name [eg. -m 192.168.10.10]\n");
				fprintf(stderr, "-q port_RC\t\tResource controller port number [eg. -q 8800]\n");
				fprintf(stderr, "-x query\t\texcute query and get result back [eg. -x '11245:1:ls -l']\n");
				fprintf(stderr, "-X query\t\texcute query without result [eg. -X '11245:mkdir /path/name']\n");
				fprintf(stderr, "-r result_IPs\t\tComma separated list of RC IPs we expect result from [eg. -r 192.168.10.100,192.168.10.101]\n");
				fprintf(stderr, "-t recv_sock_timeout\t\trecieve socket timeout [eg. -t 2]\n\n");
				fprintf(stderr, "Example\n");
				fprintf(stderr, "-------\n");
				fprintf(stderr, BOLD "./EC -n 192.168.10.1 -p 8000 -m 238.204.234.248 -q 8800  -x '11245:pwd' -c 2 \n" RESET);
				fprintf(stderr, "lists the current working directory of two RCs who are listening on the multicast address 238.204.234.248:8800.\n");
				fprintf(stderr, "This query is identified by the number 11245.\n\n");
				return 1;
			case 'c':
				create_RC = 1;
				break;
			case 'n':
				host_EC = strdup(optarg);
				break;
			case 'p':
				port_EC = atoi(optarg);
				break;
			case 'm':
				host_RC = strdup(optarg);
				break;
			case 'q':
				port_RC = atoi(optarg);
				break;
			case 'x':
				send_message = (message_t *) malloc(strlen(optarg) + 5);
				send_message->type = 'x';
				strtok(optarg,":");
				send_message->seq = atoi(optarg);
				sprintf(send_message->body, "%s", strtok(NULL, "\0"));
				break;
			case 'X':
				send_message = (message_t *) malloc(strlen(optarg) + 5);
				send_message->type = 'X';
				strtok(optarg,":");
				send_message->seq = atoi(optarg);
				sprintf(send_message->body, "%s", strtok(NULL, "\0"));
				break;
			case 'r':
				result_IPs = strdup(optarg);
				break;
			case 't':
				recv_sock_timeout = atoi(optarg);
				break;
			default:
				fprintf(stderr, "EC: missing operand. Type './EC -h' for more information.\n");
				exit(1);
	    }
	}

	if(host_EC == NULL || port_EC == 0 || host_RC == NULL || port_RC == 0 || send_message == NULL)
	{
		fprintf(stderr, "Either or all of [Local hostname/Local port #/RC hostname/RC port #/Query message] is not specified. Type './EC -h' for more information\n");
		exit(1);
	}

	int socket_desc,i, on = 1;
	struct sockaddr_in addr_EC, addr_RC;
	char addr_RC_str[16];

	message_t recv_message;
	int msgLen;
	socklen_t len = sizeof(struct sockaddr_in);

	char loopch=0;
	struct timeval timeout;

	struct RECORD_t *RECORD_ptr, *tmp_ptr, *hash_ptr = NULL;

	// Create resource controller
	if(create_RC == 1)
	{
		// Create a stream socket
		socket_desc = socket(AF_INET, SOCK_STREAM, 0);
		if (socket_desc < 0)
		{
			perror("SOCKET");
			exit(1);
		}

		// Connect to a resource controller
		memset(&addr_RC, 0, sizeof(struct sockaddr_in));
		addr_RC.sin_family = AF_INET;
		addr_RC.sin_port = htons(port_RC);
		addr_RC.sin_addr.s_addr  = inet_addr(host_RC);
		if (connect(socket_desc, (struct sockaddr *)&addr_RC, sizeof(struct sockaddr_in)) < 0)
		{
			perror("CONNECT");
			return 1;
		}

		// Send create message to the specified RC
		if (send(socket_desc, send_message, strlen(send_message->body) + 5, 0) < 0)
		{
			perror("SEND");
			exit(1);
		}
	}
	// Execute command on a resource controller
	else
	{
		// Create a datagram socket
		socket_desc = socket(AF_INET, SOCK_DGRAM, 0);
		if (socket_desc < 0)
		{
			perror("SOCKET");
			exit(1);
		}

		// Bind to a proper port number and IP address.
		memset(&addr_EC, 0, sizeof(struct sockaddr_in));
		addr_EC.sin_family = AF_INET;
		addr_EC.sin_port = htons(port_EC);
		addr_EC.sin_addr.s_addr  = inet_addr(host_EC);
		if (bind(socket_desc, (struct sockaddr*)&addr_EC, sizeof(struct sockaddr_in)))
		{
			perror("BIND");
			exit(1);
		}

		// Disable loopback so you do not receive your own multicast datagrams
		if (setsockopt(socket_desc, IPPROTO_IP, IP_MULTICAST_LOOP,(char *)&loopch, sizeof(loopch)) < 0)
		{
			perror("IP_MULTICAST_LOOP");
			exit(1);
		}

		// Send execute message to the specified RC
		addr_RC.sin_family = AF_INET;
		addr_RC.sin_port = htons(port_RC);
		addr_RC.sin_addr.s_addr  = inet_addr(host_RC);
		if (sendto(socket_desc, send_message, strlen(send_message->body) + 5, 0, (struct sockaddr *)&addr_RC, sizeof(struct sockaddr_in)) < 0)
		{
			perror("SENDTO");
			exit(1);
		}
	}

	// Wait for result data
	if(send_message->type == 'x')
	{
		// First create a hash list of result sending IPs
		strtok(result_IPs,",");
		while(result_IPs != NULL)
		{
			// Hash table implementation for c : https://github.com/troydhanson/uthash
			HASH_FIND_STR(hash_ptr, result_IPs, RECORD_ptr);
			// Only process unique result IPs
			if(RECORD_ptr == NULL)
			{
				RECORD_ptr= (struct RECORD_t*)malloc(sizeof(struct RECORD_t));
				if(RECORD_ptr == NULL)
				{
					perror("MALLOC");
					exit(1);
				}
				strcpy(RECORD_ptr->result_IPs, result_IPs);

				// Add the new record to the hash table
				HASH_ADD_STR(hash_ptr, result_IPs, RECORD_ptr);
			}
			result_IPs = strtok(NULL,",");
		};

      		// Set socket recieve timeout
		timeout.tv_sec = recv_sock_timeout;
		timeout.tv_usec = 0;
		if (setsockopt (socket_desc, SOL_SOCKET, SO_RCVTIMEO, (char *)&timeout,sizeof(struct timeval)) < 0)
		{
			perror("SO_RCVTIMEO");
			exit(1);
		}

		do{
			// Receive a reply from the server
			if(recvfrom(socket_desc, &recv_message, sizeof(message_t), 0, (struct sockaddr *)&addr_RC, (socklen_t *)&len) < 0)
			{
				perror("RECV_SOCK_TIMEOUT");
				exit(1);
			}
			msgLen = strlen(recv_message.body);

			// Convert RC address to human readable format
			inet_ntop(AF_INET, &(addr_RC.sin_addr), addr_RC_str, INET_ADDRSTRLEN);

			// Check if recieved RC IP address is part of the result IPs
			HASH_FIND_STR(hash_ptr, addr_RC_str, RECORD_ptr);
			if(RECORD_ptr != NULL)
			{
				// Display reply message
				if(recv_message.type == 'r' && recv_message.seq == send_message->seq)
				{
					// If End of Result (EOR) is part of the message, decrement the result IPs by one
					if(strncmp(recv_message.body + msgLen - 3, "EOR", 3) == 0)
					{
						// Remove the result IP record from the Hash table
						HASH_DEL(hash_ptr, RECORD_ptr);

						// EOR is sent with result
						if(msgLen > 3)
							sprintf(recv_message.body + msgLen - 3, "%s#EOR\n", addr_RC_str);
						// EOR is sent alone
						else
							sprintf(recv_message.body, "EOR\n");
					}
					printf("%s#%s", addr_RC_str, recv_message.body);
					fflush(stdout);
				}
			}
		}while(hash_ptr != NULL);
	}
}

