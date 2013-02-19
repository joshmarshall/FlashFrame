Player.swf :
	$(MXMLC_PATH) Player.as -static-link-runtime-shared-libraries=true -swf-version=11
clean :
	rm Player.swf
