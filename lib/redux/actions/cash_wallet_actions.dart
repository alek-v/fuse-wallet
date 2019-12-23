import 'package:fusecash/models/business.dart';
import 'package:fusecash/models/transfer.dart';
import 'package:fusecash/models/job.dart';
import 'package:fusecash/redux/actions/error_actions.dart';
import 'package:flutter_branch_io_plugin/flutter_branch_io_plugin.dart';
import 'package:redux/redux.dart';
import 'package:redux_thunk/redux_thunk.dart';
import 'dart:io';
import 'package:wallet_core/wallet_core.dart';
import 'package:fusecash/services.dart';
import 'package:fusecash/models/token.dart';
import 'dart:async';
import 'dart:math';
import 'dart:convert';
import 'package:decimal/decimal.dart';
import 'package:logger/logger.dart';
// import 'package:path_provider/path_provider.dart';
import 'package:flutter_android_lifecycle/flutter_android_lifecycle.dart';


// class DualOutput extends LogOutput {

//   File file;
//   DualOutput() {
//     file = null;
//   }

//   Future<File> getFile() async {
//     final directory = await getApplicationDocumentsDirectory();
//     return File(directory.path+"/logs.txt");
//   }

//   @override
//   void output(OutputEvent event) async {
//     if (file == null) {
//       file = await getFile();
//     }
//     for (var line in event.lines) {
//       print(line);
// //      await file.writeAsString(line + '\n', mode: FileMode.append);
//     }
//   }
// }

var logger = Logger(
  printer: PrettyPrinter()
  // output: DualOutput()
);

class SetDefaultCommunity {
  String defaultCommunity;
  SetDefaultCommunity(this.defaultCommunity);
}

class InitWeb3Success {
  final Web3 web3;
  InitWeb3Success(this.web3);
}

class OnboardUserSuccess {
  final String accountAddress;
  OnboardUserSuccess(this.accountAddress);
}

class GetWalletAddressSuccess {
  final String walletAddress;
  GetWalletAddressSuccess(this.walletAddress);
}

class CreateAccountWalletRequest {
  final String accountAddress;
  CreateAccountWalletRequest(this.accountAddress);
}

class CreateAccountWalletSuccess {
  final String accountAddress;
  CreateAccountWalletSuccess(this.accountAddress);
}

class GetTokenBalanceSuccess {
  final BigInt tokenBalance;
  GetTokenBalanceSuccess(this.tokenBalance);
}

class SendTokenSuccess {
  final String txHash;
  SendTokenSuccess(this.txHash);
}

class JoinCommunitySuccess {
  final String txHash;
  final String communityAddress;
  final String communityName;
  final Token token;
  JoinCommunitySuccess(
      this.txHash, this.communityAddress, this.communityName, this.token);
}

class AlreadyJoinedCommunity {
  final String communityAddress;
  final String communityName;
  final Token token;
  AlreadyJoinedCommunity(this.communityAddress, this.communityName, this.token);
}

class SwitchCommunityRequested {
  final String communityAddress;
  SwitchCommunityRequested(this.communityAddress);
}

class SwitchCommunitySuccess {
  final Token token;
  final String communityAddress;
  final String communityName;
  SwitchCommunitySuccess(this.communityAddress, this.communityName, this.token);
}

class SwitchCommunityFailed { }

class GetJoinBonusSuccess {
  // TODO
  GetJoinBonusSuccess();
}

class GetBusinessListSuccess {
  // TODO
  GetBusinessListSuccess();
}

class TransferJobSuccess {
  Job job;
  TransferJobSuccess(this.job);
}

class GetTokenTransfersListSuccess {
  List<Transfer> tokenTransfers;
  GetTokenTransfersListSuccess(this.tokenTransfers);
}

class StartBalanceFetchingSuccess {
  StartBalanceFetchingSuccess();
}

class StartTransfersFetchingSuccess {
  String tokenAddress;
  StartTransfersFetchingSuccess();
}

class TransferSendRequested {
  PendingTransfer transfer;
  TransferSendRequested(this.transfer);
}

class TransferSendSuccess {
  PendingTransfer requestedTransfer;
  PendingTransfer transfer;
  TransferSendSuccess(this.requestedTransfer, this.transfer);
}

class BranchCommunityUpdate {
  BranchCommunityUpdate();
}

class BranchCommunityToUpdate {
  final String communityAddress;
  BranchCommunityToUpdate(this.communityAddress);
}

class AddSendToInvites {
  final String jobId;
  final num amount;
  AddSendToInvites(this.jobId, this.amount);
}

class RemoveSendToInvites {
  final String jobId;
  RemoveSendToInvites(this.jobId);
}


class BranchListening {}

class BusinessesLoadedAction {
  final List<Business> businessList;

  BusinessesLoadedAction(this.businessList);
}

Future<bool> approvalCallback() async {
  return true;
}

ThunkAction listenToBranchCall() {
  return (Store store) async {
    logger.wtf("branch listening.");
    FlutterBranchIoPlugin.listenToDeepLinkStream().listen((stringData) {
      var linkData = jsonDecode(stringData);
      logger.wtf("linkData $linkData");
      if (linkData["~feature"] == "switch_community") {
        var communityAddress = linkData["community_id"];
        logger.wtf("communityAddress $communityAddress");
        store.dispatch(BranchCommunityToUpdate(communityAddress));
      }
      if (linkData["~feature"] == "invite_user") {
        var communityAddress = linkData["community_address"];
        logger.wtf("community_address $communityAddress");
        store.dispatch(BranchCommunityToUpdate(communityAddress));
      }
    }, onDone: () {
      logger.wtf("ondone");
      store.dispatch(listenToBranchCall());
    }, onError: (error) {
      logger.wtf("error, $error");
      store.dispatch(listenToBranchCall());
    });

    if (Platform.isAndroid) {
      FlutterAndroidLifecycle.listenToOnStartStream().listen((string) {
        logger.d("ONSTART");
        FlutterBranchIoPlugin.setupBranchIO();
      });
    }

    store.dispatch(BranchListening());
  };
}

ThunkAction initWeb3Call(String privateKey) {
  return (Store store) async {
    try {
      logger.d('initWeb3. privateKey: $privateKey');
      Web3 web3 = new Web3(approvalCallback);
      if (store.state.cashWalletState.communityAddress == null || store.state.cashWalletState.communityAddress.isEmpty) {
        store.dispatch(SetDefaultCommunity(web3.getDefaultCommunity()));
      }
      web3.setCredentials(privateKey);
      store.dispatch(new InitWeb3Success(web3));
    } catch (e) {
      logger.e(e);
      store.dispatch(new ErrorAction('Could not init web3'));
    }
  };
}

ThunkAction startBalanceFetchingCall() {
  return (Store store) async {
    String tokenAddress = store.state.cashWalletState.token?.address;
    if (tokenAddress != null) {
      store.dispatch(getTokenBalanceCall(tokenAddress));
    }
    new Timer.periodic(Duration(seconds: 3), (Timer t) async {
      if (store.state.cashWalletState.walletAddress == '') {
        t.cancel();
        return;
      }
      String tokenAddress = store.state.cashWalletState.token?.address;

      if (tokenAddress != null) {
        store.dispatch(getTokenBalanceCall(tokenAddress));
      }
    });
    store.dispatch(new StartBalanceFetchingSuccess());
  };
}

ThunkAction startTransfersFetchingCall() {
  return (Store store) async {
    String tokenAddress = store.state.cashWalletState.token?.address;
    if (tokenAddress != null) {
      store.dispatch(getTokenTransfersListCall(tokenAddress));
    }
    new Timer.periodic(Duration(seconds: 3), (Timer t) async {
      if (store.state.cashWalletState.walletAddress == '') {
        t.cancel();
        return;
      }
      String tokenAddress = store.state.cashWalletState.token?.address;
      if (tokenAddress != null) {
        store.dispatch(getTokenTransfersListCall(tokenAddress));
      }
    });
    store.dispatch(new StartTransfersFetchingSuccess());
  };
}

ThunkAction createAccountWalletCall(String accountAddress) {
  return (Store store) async {
    try {
      logger.d('createAccountWalletCall');
      logger.d('accountAddress: $accountAddress');
      store.dispatch(new CreateAccountWalletRequest(accountAddress));
      await api.createWallet();
      store.dispatch(new CreateAccountWalletSuccess(accountAddress));
      new Timer.periodic(Duration(seconds: 5), (Timer t) async {
        dynamic wallet = await api.getWallet();
        String walletAddress = wallet["walletAddress"];
        if (walletAddress != null && walletAddress.isNotEmpty) {
          store.dispatch(new GetWalletAddressSuccess(walletAddress));
          t.cancel();
        }
      });
    } catch (e) {
      logger.e(e);
      store.dispatch(new ErrorAction('Could not create wallet'));
    }
  };
}

ThunkAction getWalletAddressCall() {
  return (Store store) async {
    try {
      dynamic wallet = await api.getWallet();
      String walletAddress = wallet["walletAddress"];
      store.dispatch(new GetWalletAddressSuccess(walletAddress));
    } catch (e) {
      logger.e(e);
      store.dispatch(new ErrorAction('Could not get wallet address'));
    }
  };
}

ThunkAction getTokenBalanceCall(String tokenAddress) {
  return (Store store) async {
    try {
      String walletAddress = store.state.cashWalletState.walletAddress;
      // logger.d(
      //     'fetching token balance of $tokenAddress for $walletAddress wallet');
      BigInt tokenBalance =
          await graph.getTokenBalance(walletAddress, tokenAddress);
      store.dispatch(new GetTokenBalanceSuccess(tokenBalance));
    } catch (e) {
      logger.e(e);
      store.dispatch(new ErrorAction('Could not get token balance'));
    }
  };
}

ThunkAction startFetchingJobCall(String jobId) {
  return (Store store) async {
    try {
      logger.d('fetching job $jobId');
      dynamic response = await api.getJob(jobId);
      Job job = Job.fromJson(response);
      if (job.lastFinishedAt == null || job.lastFinishedAt.isEmpty) {
        Timer(Duration(seconds: 3), () {store.dispatch(startFetchingJobCall(jobId));});
        return;
      }
      logger.wtf("job.name: ${job.name}");
      switch (job.name) {
        case Job.RELAY: {
          String walletModule = job.data["walletModule"];
          logger.wtf("walletModule: $walletModule");
          switch (walletModule) {
            case Job.COMMUNITY_MANAGER: {
              // TODO nothing.
              break;
            }
            case Job.TRANSFER_MANAGER: {
              logger.wtf("dispatching");
              store.dispatch(new TransferJobSuccess(job));
              break;
            }
            default: {
              //statements;
            }
            break;
          }
          break;
        }
        case Job.CREATE_WALLET: {
          store.dispatch(callSendToInviteCall(job));
          break;
        }
        default: {

        }
        break;
      }
    } catch (e) {
      logger.e(e);
      store.dispatch(new ErrorAction('Could not get job'));
    }
  };
}

ThunkAction inviteAndSendCall(String contactPhoneNumber, num tokensAmount) {
  return (Store store) async {
    dynamic response = await api.invite(contactPhoneNumber, store.state.cashWalletState.communityAddress);
    logger.wtf("response $response");
    String jobId = response['job']['_id'].toString();
    store.dispatch(AddSendToInvites(jobId, tokensAmount));
    store.dispatch(startFetchingJobCall(jobId));
  };
}

ThunkAction sendTokenCall(String receiverAddress, num tokensAmount) {
  return (Store store) async {
    try {
      Web3 web3 = store.state.cashWalletState.web3;
      String walletAddress = store.state.cashWalletState.walletAddress;
      Token token = store.state.cashWalletState.token;
      String tokenAddress = token.address;

      Decimal tokensAmountDecimal = Decimal.parse(tokensAmount.toString());
      Decimal decimals = Decimal.parse(pow(10, token.decimals).toString());
      BigInt value = BigInt.from((tokensAmountDecimal * decimals).toInt());
      Transfer transferRequested = new PendingTransfer(
          from: walletAddress,
          to: receiverAddress,
          tokenAddress: tokenAddress,
          value: value,
          type: 'SEND');
      store.dispatch(new TransferSendRequested(transferRequested));

      logger.wtf(
          'Sending $tokensAmount tokens of $tokenAddress from wallet $walletAddress to $receiverAddress');
      dynamic response = await api.tokenTransfer(
          web3, walletAddress, tokenAddress, receiverAddress, tokensAmount);

      dynamic jobId = response['job']['_id'];
      logger.wtf('Job $jobId for sending token sent to the relay service');

      store.dispatch(startFetchingJobCall(jobId));

      Transfer transfer = new PendingTransfer(
          from: walletAddress,
          to: receiverAddress,
          tokenAddress: tokenAddress,
          value: value,
          type: 'SEND',
          jobId: jobId);
      store.dispatch(new TransferSendSuccess(transferRequested, transfer));
    } catch (e) {
      logger.e(e);
      store.dispatch(new ErrorAction('Could not send token'));
    }
  };
}

ThunkAction callSendToInviteCall(Job job) {
  return (Store store) async {
    Map<String, num> sendToInvites = store.state.cashWalletState.sendToInvites;
    store.dispatch(sendTokenCall(job.data["walletAddress"], sendToInvites[job.id]));
    store.dispatch(RemoveSendToInvites(job.id));
  };
}

ThunkAction joinCommunityCall({dynamic community, dynamic token}) {
  return (Store store) async {
    try {
      Web3 web3 = store.state.cashWalletState.web3;
      String walletAddress = store.state.cashWalletState.walletAddress;
      bool isMember = await graph.isCommunityMember(
          walletAddress, community["entitiesList"]["address"]);
      String communityAddress = community['address'];
      if (isMember) {
        return store.dispatch(new AlreadyJoinedCommunity(
            communityAddress,
            community["name"],
            new Token(
                address: token["address"],
                name: token["name"],
                symbol: token["symbol"],
                decimals: token["decimals"])));
      }
      await api.joinCommunity(web3, walletAddress, communityAddress);
      // return store.dispatch(new JoinCommunitySuccess(
      //     txHash,
      //     communityAddress,
      //     community["name"],
      //     new Token(address: token["address"], name: token["name"], symbol: token["symbol"], decimals: token["decimals"])));
    } catch (e) {
      logger.e(e);
      store.dispatch(new ErrorAction('Could not join community'));
    }
  };
}

ThunkAction switchCommunityCall(String communityAddress) {
  return (Store store) async {
    try {
      store.dispatch(new SwitchCommunityRequested(communityAddress));
      dynamic community = await graph.getCommunityByAddress(communityAddress);
      logger.d('community fetched for $communityAddress');
      dynamic token = await graph.getTokenOfCommunity(communityAddress);
      logger.d(
          'token ${token["address"]} (${token["symbol"]}) fetched for $communityAddress');
      store.dispatch(joinCommunityCall(community: community, token: token));
      return store.dispatch(new SwitchCommunitySuccess(
          communityAddress,
          community["name"],
          new Token(
              address: token["address"],
              name: token["name"],
              symbol: token["symbol"],
              decimals: token["decimals"])));
    } catch (e) {
      logger.e(e);
      store.dispatch(new ErrorAction('Could not join community'));
      store.dispatch(new SwitchCommunityFailed());
    }
  };
}

ThunkAction getJoinBonusCall() {
  return (Store store) async {
    try {
      // TODO
    } catch (e) {
      logger.e(e);
      store.dispatch(new ErrorAction('Could not get join bonus'));
    }
  };
}

ThunkAction getBusinessListCall() {
  return (Store store) async {
    try {
      var response = await api.getBusinessList(store.state.cashWalletState.communityAddress);
      List<Business> businessList = new List();
      response["data"].forEach((f) => businessList.add(new Business.fromJson(f)));
      store.dispatch(new BusinessesLoadedAction(businessList));
    } catch (e) {
      logger.e(e);
      store.dispatch(new ErrorAction('Could not get businesses list'));
    }
  };
}

ThunkAction getTokenTransfersListCall(String tokenAddress) {
  return (Store store) async {
    try {
      String walletAddress = store.state.cashWalletState.walletAddress;
      // logger.d(
      //     'fetching token transfers of $tokenAddress for $walletAddress wallet');
      Map<String, dynamic> response =
          await graph.getTransfers(walletAddress, tokenAddress);
      List<Transfer> transfers = List<Transfer>.from(
          response["data"].map((json) => Transfer.fromJson(json)).toList());
      store.dispatch(new GetTokenTransfersListSuccess(transfers));
    } catch (e) {
      logger.e(e);
      store.dispatch(new ErrorAction('Could not get token transfers'));
    }
  };
}

ThunkAction sendTokenToContactCall(
    String contactPhoneNumber, num tokensAmount) {
  return (Store store) async {
    try {
      logger.i('Trying to send $tokensAmount to phone $contactPhoneNumber');
      Map wallet = await api.getWalletByPhoneNumber(contactPhoneNumber);
      logger.wtf("wallet $wallet");
      String walletAddress = (wallet != null) ? wallet["walletAddress"]: null;
      if (walletAddress == null || walletAddress.isEmpty) {
        store.dispatch(inviteAndSendCall(contactPhoneNumber, tokensAmount));
        return;
      }
      store.dispatch(sendTokenCall(walletAddress, tokensAmount));
    } catch (e) {
      logger.e(e);
      store.dispatch(new ErrorAction('Could not send token to contact'));
    }
  };
}