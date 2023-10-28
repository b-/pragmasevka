DOCKER = docker
#DOCKER = podman

.PHONY: help, images
help: ## Show this help
	@egrep -h '\s##\s' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

all: ## build Docker images, then build font, then patch font.
	make images
	make font

images: ## Create Docker image dependencies
	make builder
	make scripter

builder: ## Create the `iosevka` builder Docker image
	$(DOCKER) build --no-cache -t iosevka/builder ./images/iosevka

scripter: ## Create the `fontforge` scripter Docker image
	$(DOCKER) build --no-cache -t fontforge/scripter ./images/fontforge

font: ## Run all build steps in correct order
	make --ignore-errors ttf
	make --ignore-errors nerd
	make --ignore-errors package

ttf: ## Build ttf font from `Pragmasevka` custom configuration
	$(DOCKER) run --rm \
		-v pragmasevka-volume:/builder/dist/pragmasevka/ttf \
		-v $(CURDIR)/private-build-plans.toml:/builder/private-build-plans.toml \
		iosevka/builder \
		npm run build -- ttf::pragmasevka
	$(DOCKER) run --rm \
		-v pragmasevka-volume:/scripter \
		-v $(CURDIR)/punctuation.py:/scripter/punctuation.py \
		fontforge/scripter \
		python /scripter/punctuation.py ./pragmasevka
	$(DOCKER) container create \
		-v pragmasevka-volume:/ttf \
		--name pragmasevka-dummy \
		alpine
	mkdir -p $(CURDIR)/dist/ttf
	$(DOCKER) cp pragmasevka-dummy:/ttf $(CURDIR)/dist
	$(DOCKER) rm pragmasevka-dummy
	$(DOCKER) volume rm pragmasevka-volume
	rm -rf $(CURDIR)/dist/ttf/*semibold*.ttf
	rm -rf $(CURDIR)/dist/ttf/*black*.ttf
	rm -rf $(CURDIR)/dist/ttf/punctuation.py

nerd: ## Patch with Nerd Fonts glyphs
	$(DOCKER) run --rm \
		-v $(CURDIR)/dist/ttf:/in \
		-v pragmasevka-volume:/out \
		nerdfonts/patcher --complete --careful
	$(DOCKER) container create \
		-v pragmasevka-volume:/nerd \
		--name pragmasevka-dummy \
		alpine
	$(DOCKER) cp pragmasevka-dummy:/nerd $(CURDIR)/dist
	$(DOCKER) rm pragmasevka-dummy
	$(DOCKER) volume rm pragmasevka-volume
	mv "$(CURDIR)/dist/nerd/Pragmasevka Nerd Font Complete.ttf" "$(CURDIR)/dist/nerd/pragmasevka-nf-regular.ttf"
	mv "$(CURDIR)/dist/nerd/Pragmasevka Italic Nerd Font Complete.ttf" "$(CURDIR)/dist/nerd/pragmasevka-nf-italic.ttf"
	mv "$(CURDIR)/dist/nerd/Pragmasevka Bold Nerd Font Complete.ttf" "$(CURDIR)/dist/nerd/pragmasevka-nf-bold.ttf"
	mv "$(CURDIR)/dist/nerd/Pragmasevka Bold Italic Nerd Font Complete.ttf" "$(CURDIR)/dist/nerd/pragmasevka-nf-bolditalic.ttf"

package: ## Pack fonts to ready-to-distribute archives
	zip -jr $(CURDIR)/dist/Pragmasevka.zip $(CURDIR)/dist/ttf/*.ttf
	zip -jr $(CURDIR)/dist/Pragmasevka_NF.zip $(CURDIR)/dist/nerd/*.ttf

clean:
	rm -rf $(CURDIR)/dist/*
