# make sim     analyze, run the testbench, write sim/out/*.png
# make check   analyze only (fast syntax and type check)
# make pieces  regenerate src/pieces.vhd
NVC  := nvc --std=1993 --work=work:build/work
SRC  := src/pieces.vhd src/art.vhd src/tetris_pkg.vhd src/ps2_keys.vhd src/game_logic.vhd \
        src/renderer.vhd src/sound.vhd src/tetris_core.vhd src/vga_timing.vhd src/clk_div2.vhd src/vga_out.vhd src/hex4.vhd src/tetricide.vhd
TB   := sim/tb_core.vhd

.PHONY: check sim sound pieces art diagram schematic qar clean

check:
	@mkdir -p build
	$(NVC) -a $(SRC)

sim: check
	@mkdir -p sim/out
	$(NVC) -a $(TB) -e tb_core -r
	@for f in sim/out/*.ppm; do magick "$$f" "$${f%.ppm}.png" && rm "$$f"; done
	@ls sim/out

sound: check
	@mkdir -p sim/out
	$(NVC) -a sim/tb_sound.vhd -e tb_sound -r

pieces:
	python3 tools/gen_pieces.py

clean:
	rm -rf build sim/out

art:
	python3 tools/gen_art.py

diagram:
	@mkdir -p build
	pdflatex -interaction=nonstopmode -halt-on-error -output-directory=build docs/block-diagram.tex >/dev/null
	pdftocairo -svg build/block-diagram.pdf docs/block-diagram.svg
	@echo "→ docs/block-diagram.svg"

# Quartus archive: everything flat in one folder, the way the lab's projects are
QAR_FILES := tetricide.qpf tetricide.qsf tetricide_top.bdf $(notdir $(SRC)) \
             $(notdir $(wildcard quartus/*.bsf))
qar: schematic
	@rm -rf build/qar && mkdir -p build/qar
	cp quartus/* $(SRC) build/qar/
	python3 tools/qar.py pack tetricide.qar build/qar $(QAR_FILES)

schematic:
	python3 tools/gen_bdf.py
