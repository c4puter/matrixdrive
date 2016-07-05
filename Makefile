PROJECT = matrixdrive
OBJECTS = main.o

CC = avr-gcc
OBJDUMP = avr-objdump
SIZE = avr-size

CFLAGS = -mmcu=atxmega8e5 -DF_CPU=2000000uLL -std=c11 -Wall -Wextra -Werror \
		 -O2 -flto -g

.PHONY:	all clean

all:	${PROJECT}.elf ${PROJECT}.disasm

%.disasm: %.elf
	${OBJDUMP} -S $< > $@

${PROJECT}.elf:	${OBJECTS}
	${CC} -o $@ ${CFLAGS} ${LDFLAGS} $^
	${SIZE} $@

clean:
	rm -f ${PROJECT}.elf ${PROJECT}.disasm ${OBJECTS}

