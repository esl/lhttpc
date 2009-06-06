APPLICATION := lhttpc
APP_FILE := ebin/$(APPLICATION).app
SOURCES := $(wildcard src/*.erl)
HEADERS := $(wildcard src/*.hrl)
MODULES := $(patsubst src/%.erl,%,$(SOURCES))
BEAMS := $(patsubst %,ebin/%.beam,$(MODULES))

comma := ,
e :=
space := $(e) $(e)
MODULELIST := $(subst $(space),$(comma),$(MODULES))

TEST_SOURCES := $(wildcard test/*.erl)
TEST_BEAMS := $(patsubst %.erl,%.beam, $(TEST_SOURCES))

include vsn.mk

SSL_VERSION=$(shell ./ssl_version)

.PHONY: all clean dialyzer

all: $(APPLICATION) doc

$(APPLICATION): $(BEAMS) $(APP_FILE)

test: $(APPLICATION) $(TEST_BEAMS)
	@echo Running tests
	@erl -pa ebin/ -pa test/ -noinput -eval 'eunit:test(run_test)' -s erlang halt

test/%.beam: test/%.erl
	@echo Compiling $<
	@erlc -o test/ $<

$(APP_FILE): src/$(APPLICATION).app.src
	@echo Generating $@
	@sed -e 's/@MODULES@/$(MODULELIST)/' -e 's/@VSN@/$(VSN)/' $< > $@

ebin/%.beam: src/%.erl $(HEADERS) $(filter-out $(wildcard ebin), ebin)
	@echo Compiling $<
	@erlc -D$(SSL_VERSION) -o ebin/ $<

ebin:
	@echo Creating ebin/
	@mkdir ebin/

doc: doc/edoc-info

dialyzer:
	@echo Running dialyzer on sources
	@dialyzer --src -r src/

doc/edoc-info: doc/overview.edoc $(SOURCES) 
	@echo Generating documentation from edoc
	@erl -noinput -eval 'edoc:application(gen_httpd, "./", [{doc, "doc/"}])' -s erlang halt

clean:
	@echo Cleaning
	@rm -f ebin/*.{beam,app} test/*.beam doc/*.{html,css,png} doc/edoc-info
