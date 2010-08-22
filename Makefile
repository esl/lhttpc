REBAR := ./rebar

.PHONY: all clean test dialyzer

all:
	$(REBAR) compile

test:
	$(REBAR) eunit

dialyzer:
	$(REBAR) analyze

clean:
	$(REBAR) clean

release: all dialyzer test
	$(REBAR) release
