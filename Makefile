REBAR := ./rebar

.PHONY: all doc clean test dialyzer

all: compile doc

compile:
	$(REBAR) compile

doc:
	$(REBAR) doc

test:
	$(REBAR) eunit

dialyzer:
	$(REBAR) analyze

release: all dialyzer test
	$(REBAR) release

clean:
	$(REBAR) clean
