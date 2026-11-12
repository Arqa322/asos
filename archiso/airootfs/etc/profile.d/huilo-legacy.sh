# Old command names (asos-* ...) keep working through huilo-legacy; the
# directory goes to the END of PATH so it never shadows a real command.
case ":$PATH:" in
	*:/usr/local/lib/huilo/legacy:*) ;;
	*) PATH="$PATH:/usr/local/lib/huilo/legacy" ;;
esac
export PATH
