import sys,struct
KEY=bytes.fromhex("7c4e0304550509072d2c7b38170d1711")
def rc4(data):
    S=list(range(256));j=0
    for i in range(256):
        j=(j+S[i]+KEY[i%16])&255;S[i],S[j]=S[j],S[i]
    i=j=0;out=bytearray()
    for b in data:
        i=(i+1)&255;j=(j+S[i])&255;S[i],S[j]=S[j],S[i];out.append(b^S[(S[i]+S[j])&255])
    return bytes(out)
ddr,mini,out=sys.argv[1:4]
s1=open(ddr,'rb').read(); s2=open(mini,'rb').read()
s1+=b'\0'*(-len(s1)%2048)
init_size=len(s1)//512; init_boot=init_size+1024
h=bytearray(512)
struct.pack_into('<I',h,0,0x0ff0aa55); struct.pack_into('<I',h,8,1); struct.pack_into('<H',h,12,4)
struct.pack_into('<HH',h,506,init_size,init_boot)
img=rc4(bytes(h))+b'\0'*1536+s1+s2
open(out,'wb').write(img); print(f"{out}: {len(img)} bytes init_size={init_size} init_boot_size={init_boot}")
