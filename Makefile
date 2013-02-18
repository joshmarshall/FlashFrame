Player.swf :
	$(MXMLC_PATH) Player.as -static-link-runtime-shared-libraries=true
clean :
	rm Player.swf
