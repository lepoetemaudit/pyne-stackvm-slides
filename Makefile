render:
	pandoc -t dzslides -s slides.md -o slides.html --normalize --mathml --tab-stop=2 --template templates/default.dzslides
