// Copyright 2024-2025 Apple Inc. and the Swift Homomorphic Encryption project authors
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import HomomorphicEncryption
import HomomorphicEncryptionProtobuf
import Hummingbird
import Logging
import NIO
import PrivateInformationRetrieval
import Util

struct AppContext: IdentifiedRequestContext, AuthenticatedRequestContext, PlatformRequestContext, RequestContext {
    var coreContext: CoreRequestContextStorage
    var userIdentifier: UserIdentifier
    var userTier: UserTier
    var platform: Platform?

    // override upload size to 10MiB, the default 2MiB limit is too small for some evaluation keys.
    var maxUploadSize: Int {
        10 * 1024 * 1024
    }

    init(source: ApplicationRequestContextSource) {
        self.coreContext = .init(source: source)
        self.platform = nil
        self.userIdentifier = UserIdentifier(identifier: "")
        self.userTier = .tier1
    }
}

func loadUsecase(usecase: ServerConfiguration.Usecase) throws -> Usecase {
    do {
        return try PirUsecase<MulPirServer<Bfv<UInt32>>>(usecase: usecase)
    } catch {
        return try PirUsecase<MulPirServer<Bfv<UInt64>>>(usecase: usecase)
    }
}

func buildApplication(
    configuration: ApplicationConfiguration = .init(),
    usecaseStore: UsecaseStore = UsecaseStore(),
    privacyPassState: PrivacyPassState<UserAuthenticator>? = nil,
    evaluationKeyStore: some PersistDriver = MemoryPersistDriver()) async throws -> some ApplicationProtocol
{
    let router = Router(context: AppContext.self)
    router.middlewares.add(LogRequestsMiddleware(.info, includeHeaders: .none))
    router.middlewares.add(LogErrorsMiddleware())

    let pirServiceController = PIRServiceController(usecases: usecaseStore, evaluationKeyStore: evaluationKeyStore)
    let pirGroup = router.group()

    if let privacyPassState {
        let controller = PrivacyPassController(state: privacyPassState)
        controller.addRoutes(to: router.group())
        let userTierAuthenticator = AuthenticateUserTierMiddleware(AppContext.self, state: privacyPassState)
        pirGroup.add(middleware: userTierAuthenticator)
    }

    pirServiceController.addRoutes(to: pirGroup)

    var application = Application(router: router, configuration: configuration)
    application.addServices(evaluationKeyStore)

    return application
}
