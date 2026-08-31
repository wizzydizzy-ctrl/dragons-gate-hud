local SHA256=require("sha256")
test("hashes empty SHA-256 known-answer vector",function() eq(SHA256.hex(""),"e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855") end)
test("hashes abc SHA-256 known-answer vector",function() eq(SHA256.hex("abc"),"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") end)
