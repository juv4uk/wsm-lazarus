#!/usr/bin/env python3
"""Core1.3: FPC Core1 перше визначення проти pinned фізичного D4 SENS."""
import pathlib
import subprocess
import sys
import tempfile

cli,oracle,root = sys.argv[1:4]
root=pathlib.Path(root)
def must(ok,why):
    if not ok: raise AssertionError(why)
def pack(words):
    trits=[]
    for i,w in enumerate(words):
        must(w and set(w)<={"0","1"},"хибні слова тесту")
        if i: trits.append(2)
        trits.extend(map(int,w))
    trits.extend([2]*((-len(trits))%5))
    return bytes(sum(trits[i+j]*3**(4-j) for j in range(5))
                 for i in range(0,len(trits),5))
def unpack(data):
    trits=[]
    for b in data:
        must(b<243,"поганий T5M byte")
        trits.extend((b//div)%3 for div in (81,27,9,3,1))
    out=[]; current=[]
    for t in trits:
        if t==2:
            if current: out.append("".join(current));current=[]
        else: current.append(str(t))
    if current: out.append("".join(current))
    return out
def run(args,input_data=None):
    return subprocess.run(args,stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,timeout=90,input=input_data)
with tempfile.TemporaryDirectory(prefix="core1-pershyi-") as td:
    temp=pathlib.Path(td)
    cases=(("нуль",["1","0","1"],"0","(ядро1-другий-елемент (список так ні так))","НІ"),
           ("один",["0","1","0"],"1","(ядро1-другий-елемент (список ні так ні))","ТАК"),
           ("порожній",["1","000","0"],"000","(ядро1-другий-елемент (список так () ні))","()"))
    forms=[];expected_projection=[]
    for label,vals,expected,form,projection in cases:
        a=["10","1110",*vals,"01"]
        path=temp/(label+".sens");path.write_bytes(pack(a))
        native=run([cli,"--виконати-перший",str(root),str(path)])
        must(native.returncode==0 and b"0 unfreed memory blocks" in native.stderr,
             label+" FPC: "+native.stderr.decode(errors="replace"))
        must(native.stdout==pack([expected]),label+" неканонічна відповідь")
        forms.append(form);expected_projection.append(projection)
    # The second item is itself a physical D2 list.  A selector must return
    # the exact nested value; it must not narrow list contents to atoms.
    nested=["10","1110","1","10","1110","1","0","01","0","01"]
    nested_path=temp/"вкладене.sens";nested_path.write_bytes(pack(nested))
    native=run([cli,"--виконати-перший",str(root),str(nested_path)])
    must(native.returncode==0 and b"0 unfreed memory blocks" in native.stderr,
         "вкладений фізичний елемент FPC: "+native.stderr.decode(errors="replace"))
    must(native.stdout==pack(["10","1110","1","0","01"]),
         "вкладений елемент не збережений як точна фізична структура")
    forms.append("(ядро1-другий-елемент (список так (список так ні) ні))")
    expected_projection.append("(ТАК НІ)")
    repl_input=(":мова укр\n:завантажити "+
        str(root/"external/sens/lib/core1.lisp")+"\n"+
        "\n".join(forms)+"\n").encode("utf-8")
    actual=run([oracle,"--surface=uk"],input_data=repl_input)
    must(actual.returncode==0 and actual.stderr==b"",
         "SENS REPL/укр: "+actual.stderr.decode(errors="replace"))
    for projection in expected_projection:
        marker=("sens[укр]> "+projection+"\nsens[укр]> ").encode("utf-8")
        must(marker in actual.stdout,
             "SENS REPL не повернув проєкцію "+projection+
             ": "+actual.stdout.decode(errors="replace")[-500:])
    def reject(words,label,rt=root,extension=".sens",code=2):
        path=temp/("відмова"+extension)
        path.write_bytes(words)
        found=run([cli,"--виконати-перший",str(rt),str(path)])
        must(found.returncode==code,label+": exit "+str(found.returncode))
        must(found.stdout==b"",label+": частковий stdout")
        must(b"CORE1-" in found.stderr,label+": без діагностики")
        if code==2:
            must(b"0 unfreed memory blocks" in found.stderr,
                 label+": не звільнено heaptrc-пам’ять після помилки")
    reject(pack(["10","1110","1","01"]),"немає другого")
    # Порожній D4:1110 список — окрема структурна помилка селектора,
    # не допустимий D1:0 та не успішне повернення D3:000.
    reject(pack(["10","1110","01"]),"порожній фізичний D4-список")
    # D3:000 є порожнім структурним значенням, а не списком-аргументом
    # з фізичним конструктором D4:1110. Host не має дописувати його сам.
    reject(pack(["000"]),"D3:000 замість фізичного списку")
    reject(pack(["1"]),"не D4:1110")
    reject(pack(["10","1110","1","0"]),"D2 EOF")
    reject(pack(["10","1110","1","0","01","1"]),"зайвий корінь")
    reject(bytes([243]),"пошкоджений T5M")
    reject(b"","порожній аргумент")
    reject(pack(["10","1110","0","1","01"]),"підміна .lisp",
           extension=".lisp",code=64)
    reject(pack(["10","1110","0","1","01"]),"немає pinned Core1",
           rt=temp/"неіснуючий")
    # Зміна реального фізичного Core1, не фальшивої текстової проєкції.
    altered=temp/"змінений"
    (altered/"external/sens/lib").mkdir(parents=True)
    core=altered/"external/sens/lib/core1.sens"
    original=(root/"external/sens/lib/core1.sens").read_bytes()
    (altered/"external/sens/lib/core4.sens").symlink_to(
        (root/"external/sens/lib/core4.sens").resolve())
    core.write_bytes(original+b"\xff")
    reject(pack(["10","1110","0","1","01"]),"пізня корупція Core1",rt=altered)
    words=unpack(original)
    first=words.index("1001")
    words[first]="1000"  # незалежний однобітний D4 контрприклад
    core.write_bytes(pack(words))
    reject(pack(["10","1110","0","1","01"]),"підміна тіла Core1",rt=altered)
    good=temp/"після.sens";good.write_bytes(pack(["10","1110","1","0","01"]))
    recovered=run([cli,"--виконати-перший",str(root),str(good)])
    must(recovered.returncode==0 and recovered.stdout==pack(["0"]) and
         b"0 unfreed memory blocks" in recovered.stderr,
         "після помилок відсутнє відновлення")
    print("CORE1-ПЕРШИЙ-ВИКОНАНО-ГАРАЗД фізичних=4 "
          "SENS-оракул=4 негативів=12 D4=1001 D7=точні "
          "GC=не-інтегровано REPL=не-повний")
