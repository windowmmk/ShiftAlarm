/// 標準比特幣（Bitcoin）Base58 編碼與解碼模組
/// 排除 0, O, I, l 以及 + 和 /，具備：
/// 1. 手機雙擊 100% 準確全選（無標點符號截斷）
/// 2. 避免聊天軟體 Markdown（粗體、斜體、下劃線）解析干擾
/// 3. 無視覺易混淆字元，適合跨端傳送
library;

const String _kAlphabet =
    '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

final Map<int, int> _kAlphabetMap = {
  for (int i = 0; i < _kAlphabet.length; i++) _kAlphabet.codeUnitAt(i): i,
};

/// 將位元組陣列編碼為 Base58 字串（保留前導 0 位元組為 '1'）
String base58Encode(List<int> bytes) {
  if (bytes.isEmpty) return '';

  // 1. 計算前導 0 位元組數量
  int leadingZeros = 0;
  while (leadingZeros < bytes.length && bytes[leadingZeros] == 0) {
    leadingZeros++;
  }

  // 2. 將位元組陣列轉為 BigInt（若全為 0 則直接返回對應數量的 '1'）
  if (leadingZeros == bytes.length) {
    return '1' * leadingZeros;
  }

  final hex = bytes
      .sublist(leadingZeros)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  var intVal = BigInt.parse(hex, radix: 16);

  // 3. 重複除以 58 取餘數
  final radix58 = BigInt.from(58);
  final buffer = <int>[];
  while (intVal > BigInt.zero) {
    final mod = (intVal % radix58).toInt();
    intVal ~/= radix58;
    buffer.add(_kAlphabet.codeUnitAt(mod));
  }

  // 4. 前導 0 位元組補 '1'，並將餘數倒序組合
  final ones = List.filled(leadingZeros, _kAlphabet.codeUnitAt(0));
  return String.fromCharCodes([...ones, ...buffer.reversed]);
}

/// 將 Base58 字串解碼為原始位元組陣列
List<int> base58Decode(String text) {
  final clean = text.trim();
  if (clean.isEmpty) return [];

  // 1. 計算前導 '1' 的數量
  int leadingOnes = 0;
  while (leadingOnes < clean.length && clean[leadingOnes] == '1') {
    leadingOnes++;
  }

  // 2. 解析剩餘字元為 BigInt
  var intVal = BigInt.zero;
  final radix58 = BigInt.from(58);

  for (int i = leadingOnes; i < clean.length; i++) {
    final code = clean.codeUnitAt(i);
    final val = _kAlphabetMap[code];
    if (val == null) {
      throw FormatException('無效的 Base58 字元: "${clean[i]}" (位置: $i)');
    }
    intVal = intVal * radix58 + BigInt.from(val);
  }

  // 3. BigInt 轉回位元組陣列
  final bytes = <int>[];
  if (intVal > BigInt.zero) {
    var hex = intVal.toRadixString(16);
    if (hex.length % 2 != 0) hex = '0$hex';
    for (int i = 0; i < hex.length; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
  }

  // 4. 前導 '1' 還原為 0x00 位元組
  return [...List.filled(leadingOnes, 0), ...bytes];
}

/// 快速檢查字串是否為合法的 Base58 字母集
bool isBase58(String text) {
  final clean = text.trim();
  if (clean.isEmpty) return false;
  for (int i = 0; i < clean.length; i++) {
    if (!_kAlphabetMap.containsKey(clean.codeUnitAt(i))) return false;
  }
  return true;
}
