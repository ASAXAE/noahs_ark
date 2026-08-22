import 'dart:async';

/// Converts technical authentication failures into messages suitable for users.
String authErrorMessage(Object error) {
  final rawMessage = error.toString().replaceFirst('Exception: ', '').trim();
  final normalizedMessage = rawMessage.toLowerCase();

  if (error is TimeoutException || normalizedMessage.contains('timeout')) {
    return '连接服务器超时，请检查网络后重试';
  }

  if (normalizedMessage.contains('socketexception') ||
      normalizedMessage.contains('connection failed') ||
      normalizedMessage.contains('connection refused') ||
      normalizedMessage.contains('network is unreachable') ||
      normalizedMessage.contains('clientexception')) {
    return '无法连接服务器，请确认网络和后端服务是否正常';
  }

  const translatedMessages = <String, String>{
    'email is already registered': '该邮箱已注册，请直接登录',
    'invalid email or password': '邮箱或密码错误',
    'invalid registration data': '注册信息不符合要求，请检查后重试',
    'invalid login data': '登录信息不完整，请检查后重试',
    'failed to register user': '注册失败，请稍后重试',
    'failed to log in user': '登录失败，请稍后重试',
    'authentication required': '请先登录后再继续',
    'invalid authorization header': '登录信息格式错误，请重新登录',
    'invalid access token': '登录状态无效，请重新登录',
    'invalid or expired access token': '登录已过期，请重新登录',
    'user account not found': '找不到该用户账户',
  };

  final translatedMessage = translatedMessages[normalizedMessage];
  if (translatedMessage != null) {
    return translatedMessage;
  }

  if (RegExp(r'[\u4e00-\u9fff]').hasMatch(rawMessage)) {
    return rawMessage;
  }

  return '操作失败，请稍后重试';
}
