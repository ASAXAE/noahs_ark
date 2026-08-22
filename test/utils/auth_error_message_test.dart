import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:noahs_ark_app/utils/auth_error_message.dart';

void main() {
  group('authErrorMessage', () {
    test('translates a duplicate email error', () {
      expect(
        authErrorMessage(Exception('Email is already registered')),
        '该邮箱已注册，请直接登录',
      );
    });

    test('translates invalid credentials', () {
      expect(
        authErrorMessage(Exception('Invalid email or password')),
        '邮箱或密码错误',
      );
    });

    test('translates timeout errors', () {
      expect(
        authErrorMessage(TimeoutException('request timed out')),
        '连接服务器超时，请检查网络后重试',
      );
    });

    test('does not replace an existing Chinese message', () {
      expect(authErrorMessage(Exception('登录失败，请重试')), '登录失败，请重试');
    });
  });
}
