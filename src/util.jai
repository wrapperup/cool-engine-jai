temp_c_string :: () -> *u8 #expand {
	c_string := to_c_string(path);
	`defer free(c_string);

    return c_string;
}
