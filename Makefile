MD=$(wildcard posts/*.md)
INDEX=index.html
POSTS=$(MD:.md=.html)

all: $(INDEX) $(POSTS)

index.html : index.md templates/index-templ.html
	pandoc $< -o $@ --css css/pandoc.css -s --template=templates/index-templ.html -T Luminarys -f markdown --email-obfuscation=javascript

posts/%.html : posts/%.md templates/post-templ.html
	pandoc $< -o $@ --css css/pandoc.css -s --template=templates/post-templ.html -T Luminarys -f markdown --email-obfuscation=javascript --mathjax

clean:
	rm *.html
	rm posts/*.html
