import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:noahs_ark_app/utils/auth_error_message.dart';
import 'package:noahs_ark_app/services/api_exception.dart';

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

  test('translates verification resend rate limiting', () {
    expect(
      authErrorMessage(
        const ApiException(
          statusCode: 429,
          message: 'Please wait before requesting another verification email',
        ),
      ),
      '请求过于频繁，请稍后再试',
    );
  });

  test('translates an invalid verification token', () {
    expect(
      authErrorMessage(
        const ApiException(
          statusCode: 400,
          message: 'Invalid or expired verification token',
        ),
      ),
      '验证令牌无效、已过期或已经使用',
    );
  });

  test('translates unavailable email delivery', () {
    expect(
      authErrorMessage(
        const ApiException(
          statusCode: 503,
          message: 'Email delivery is not configured',
        ),
      ),
      '本地邮件发送尚未启用',
    );
  });

  test('translates an expired refresh token', () {
    expect(
      authErrorMessage(
        const ApiException(
          statusCode: 401,
          message: 'Invalid or expired refresh token',
        ),
      ),
      '登录已过期，请重新登录',
    );
  });

  test('translates a refresh failure', () {
    expect(
      authErrorMessage(
        const ApiException(
          statusCode: 500,
          message: 'Failed to refresh session',
        ),
      ),
      '无法续期登录状态，请重新登录',
    );
  });

  test('translates a logout failure', () {
    expect(
      authErrorMessage(
        const ApiException(statusCode: 500, message: 'Failed to log out'),
      ),
      '退出登录失败，请稍后重试',
    );
  });
}
