import 'dart:async';
import 'dart:convert';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:crypto/crypto.dart';

import 'package:bot_toast/bot_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/hbbs/hbbs.dart';
import 'package:flutter_hbb/models/ab_model.dart';
import 'package:get/get.dart';

import '../common.dart';
import '../utils/http_service.dart' as http;
import 'model.dart';
import 'platform_model.dart';

bool refreshingUser = false;

class UserModel {
  final RxString userName = ''.obs;
  final RxString userLogin = ''.obs;
  final RxBool isAdmin = false.obs;
  final RxString networkError = ''.obs;
  bool get isLogin => userName.isNotEmpty;
  WeakReference<FFI> parent;

  UserModel(this.parent) {
    userName.listen((p0) {
      // When user name becomes empty, show login button
      // When user name becomes non-empty:
      //  For _updateLocalUserInfo, network error will be set later
      //  For login success, should clear network error
      networkError.value = '';
    });
  }
//md5
  String generateMd5(String input) {
  return md5.convert(utf8.encode(input)).toString();
 }
  //AES 加密
  String encryptMessage(String message, String keyString,String IvString) {
  final key = encrypt.Key.fromBase64(keyString);
  final iv = encrypt.IV.fromBase64(IvString);//encrypt.IV.fromLength(16); // 或者使用固定的 IV
  final encrypter = encrypt.Encrypter(encrypt.AES(key));

  // 加密
  final encrypted = encrypter.encrypt(message, iv: iv);
  return encrypted.base64; // 返回 base64 编码
}
  //AES 解密
  String decryptMessage(String message, String keyString,String IvString) {
  final key = encrypt.Key.fromBase64(keyString);
  final iv = encrypt.IV.fromBase64(IvString);//encrypt.IV.fromLength(16); // 或者使用固定的 IV
  final encrypter = encrypt.Encrypter(encrypt.AES(key));

  // 解密base64
  final decrypted = encrypter.decrypt64(message, iv: iv);
  return decrypted; // 返回 明文
}
  
  void refreshCurrentUser() async {
    if (bind.isDisableAccount()) return;
    networkError.value = '';
    final token = bind.mainGetLocalOption(key: 'access_token');
    if (token == '') {
      await updateOtherModels();
      return;
    }
    _updateLocalUserInfo();
    final url = await bind.mainGetApiServer();
    final body = {
      'id': await bind.mainGetMyId(),
      'uuid': await bind.mainGetUuid()
    };
    if (refreshingUser) return;
    try {
      refreshingUser = true;
      final http.Response response;
      try {
        response = await http.post(Uri.parse('$url/api/currentUser'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token'
            },
            body: json.encode(body));
      } catch (e) {
        networkError.value = e.toString();
        rethrow;
      }
      refreshingUser = false;
      final status = response.statusCode;
      if (status == 401 || status == 400) {
        reset(resetOther: status == 401);
        return;
      }
      final data = json.decode(utf8.decode(response.bodyBytes));
      final error = data['error'];
      if (error != null) {
        throw error;
      }

      final user = UserPayload.fromJson(data);
      _parseAndUpdateUser(user);
    } catch (e) {
      debugPrint('Failed to refreshCurrentUser: $e');
    } finally {
      refreshingUser = false;
      await updateOtherModels();
    }
  }

  static Map<String, dynamic>? getLocalUserInfo() {
    final userInfo = bind.mainGetLocalOption(key: 'user_info');
    if (userInfo == '') {
      return null;
    }
    try {
      return json.decode(userInfo);
    } catch (e) {
      debugPrint('Failed to get local user info "$userInfo": $e');
    }
    return null;
  }

  _updateLocalUserInfo() {
    final userInfo = getLocalUserInfo();
    if (userInfo != null) {
      userName.value = userInfo['name'];
    }
  }

  Future<void> reset({bool resetOther = false}) async {
    await bind.mainSetLocalOption(key: 'access_token', value: '');
    await bind.mainSetLocalOption(key: 'user_info', value: '');
    if (resetOther) {
      await gFFI.abModel.reset();
      await gFFI.groupModel.reset();
    }
    userName.value = '';
  }
  
 Future<bool> test() async {
    final url = await bind.mainGetApiServer();
    final body = {
      'id': await bind.mainGetMyId(),
      'uuid': await bind.mainGetUuid(),
      'username': gFFI.userModel.userName.value
    };
  
    final http.Response response;
    try {
      response = await http.post(Uri.parse('$url/api/currentUser'),
          headers: {
            'Content-Type': 'application/json'
          },
          body: json.encode(body));
    } catch (e) {
      return false;
    }
    final status = response.statusCode;
    if (status == 401 || status == 400) {
      //reset(resetOther: status == 401);
      return false;
    }
    final data = json.decode(utf8.decode(response.bodyBytes));
    final error = data['error'];
    if (error != null) {
      return false;
    }
    //把日期写到名字里 显示在前台
    if(data['name']!=null && gFFI.userModel.userName.value==data['name'])
    {   
      final expdate = data['expdate'];
      if (expdate != null) {
         gFFI.userModel.userLogin.value = "用户名:" + data['name'] + ",有效期:" + data['expdate'];
         //gFFI.userModel.userName.value = data['name'] + "_有效期:" + data['expdate'];
      }
      return true;
    }
    else
    {
       return false;
    }
  }
  
  _parseAndUpdateUser(UserPayload user) {
    userName.value = user.name;
    userLogin.value = user.name;
    isAdmin.value = user.isAdmin;
    bind.mainSetLocalOption(key: 'user_info', value: jsonEncode(user));
  }

  // update ab and group status
  static Future<void> updateOtherModels() async {
    await Future.wait([
      gFFI.abModel.pullAb(force: ForcePullAb.listAndCurrent, quiet: false),
      gFFI.groupModel.pull()
    ]);
  }

  Future<void> logOut({String? apiServer}) async {
     await reset(resetOther: true);
   /* final tag = gFFI.dialogManager.showLoading(translate('Waiting'));
    try {
      final url = apiServer ?? await bind.mainGetApiServer();
      final authHeaders = getHttpHeaders();
      authHeaders['Content-Type'] = "application/json";
      await http
          .post(Uri.parse('$url/api/logout'),
              body: jsonEncode({
                'id': await bind.mainGetMyId(),
                'uuid': await bind.mainGetUuid(),
              }),
              headers: authHeaders)
          .timeout(Duration(seconds: 2));
    } catch (e) {
      debugPrint("request /api/logout failed: err=$e");
    } finally {
      await reset(resetOther: true);
      gFFI.dialogManager.dismissByTag(tag);
    }
    */
  }

  /// throw [RequestException]
  Future<LoginResponse> login(LoginRequest loginRequest) async {
    final url = await bind.mainGetApiServer();
/*
    final body = {
      'id': loginRequest.id,
      'uuid': loginRequest.uuid,
      'username': loginRequest.username,
      'password': loginRequest.password,
    };
    */
     DateTime now = DateTime.now();
  
  // Get milliseconds since epoch
  int millisecondsSinceEpoch = (now.millisecondsSinceEpoch / 1000).floor();
  String timestamp = millisecondsSinceEpoch.toString();

   String messageid = loginRequest.id!;
    String messageuuid = loginRequest.uuid!;
    String messageusername = loginRequest.username!;
    String messagepassword = loginRequest.password!;
    
  var data = messageid + '|' + messageuuid + '|' + messageusername + '|' + messagepassword + '|' + timestamp;
  final sign = generateMd5(data);
  final secretKey ='MTIzNDU2Nzg5ODEyMzQ1Njc4OTAxMjM0NTY3ODkwMTI=';
  final secretIv ='MTIzNDU2Nzg5ODEyMzQ1Ng==' ;
  final data2 = encryptMessage(data, secretKey,secretIv); //AES 或 RSA 加密 data，根据后台设定使用对应的加密函数
  data = decryptMessage(data2, secretKey,secretIv);
    final bodys = {
      'data': data2,
      'sign': data,
      'timestamp': timestamp
    };
        
    final resp = await http.post(Uri.parse('$url/api/login'),
        body: jsonEncode(bodys));//jsonEncode(loginRequest.toJson()));

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(resp.bodyBytes));
    } catch (e) {
      debugPrint("login: jsonDecode resp body failed: ${e.toString()}");
      if (resp.statusCode != 200) {
        BotToast.showText(
            contentColor: Colors.red, text: 'HTTP ${resp.statusCode}');
      }
      rethrow;
    }
    if (resp.statusCode != 200) {
      throw RequestException(resp.statusCode, body['error'] ?? '');
    }
    if (body['error'] != null) {
      throw RequestException(0, body['error']);
    }

    return getLoginResponseFromAuthBody(body);
  }

  LoginResponse getLoginResponseFromAuthBody(Map<String, dynamic> body) {
    final LoginResponse loginResponse;
    try {
      loginResponse = LoginResponse.fromJson(body);
    } catch (e) {
      debugPrint("login: jsonDecode LoginResponse failed: ${e.toString()}");
      rethrow;
    }

    if (loginResponse.user != null) {
      _parseAndUpdateUser(loginResponse.user!);
    }

    return loginResponse;
  }

  static Future<List<dynamic>> queryOidcLoginOptions() async {
    try {
      final url = await bind.mainGetApiServer();
      if (url.trim().isEmpty) return [];
      final resp = await http.get(Uri.parse('$url/api/login-options'));
      final List<String> ops = [];
      for (final item in jsonDecode(resp.body)) {
        ops.add(item as String);
      }
      for (final item in ops) {
        if (item.startsWith('common-oidc/')) {
          return jsonDecode(item.substring('common-oidc/'.length));
        }
      }
      return ops
          .where((item) => item.startsWith('oidc/'))
          .map((item) => {'name': item.substring('oidc/'.length)})
          .toList();
    } catch (e) {
      debugPrint(
          "queryOidcLoginOptions: jsonDecode resp body failed: ${e.toString()}");
      return [];
    }
  }
}
