MD=$(wildcard *.md)
PAGES=$(MD:.md=.html)

all: $(PAGES)

%.html : %.md
	pandoc $< -o $@ --css pandoc.css -s

clean:
	rm *.html
