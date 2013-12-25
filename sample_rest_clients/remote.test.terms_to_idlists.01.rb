echo "     ##### Local - valid id/password #####     "
ruby ./test.terms_to_idlists.01.rb "priancho@gmail.com" "peisia00" "http://pubdictionaries.dbcls.jp/dictionaries/EntrezGene%20-%20Homo%20Sapiens"
echo "     ##### Local - valid guest #####     "
ruby ./test.terms_to_idlists.01.rb "" "" "http://pubdictionaries.dbcls.jp/dictionaries/EntrezGene%20-%20Homo%20Sapiens"
echo "     ##### Local - invalid email #####     "
ruby ./test.terms_to_idlists.01.rb "priancho@---gmail.com" "password" "http://pubdictionaries.dbcls.jp/dictionaries/EntrezGene%20-%20Homo%20Sapiens"
echo "     ##### Local - invalid password#####     "
ruby ./test.terms_to_idlists.01.rb "priancho@gmail.com" "pass--word" "http://pubdictionaries.dbcls.jp/dictionaries/EntrezGene%20-%20Homo%20Sapiens"
echo "     ##### Local - invalid uri #####     "
ruby ./test.terms_to_idlists.01.rb "priancho@gmail.com" "password" "http://pubdictionaries.dbcls.jp/dictionaries"
