/*
 
 The MIT License (MIT)
 Copyright (c) 2017 Dalton Hinterscher
 
 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"),
 to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
 and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR
 ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH
 THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 
 */

import AlamoRecord
import Alamofire
import AlamofireObjectMapper
import ObjectMapper

public class SpartanRequestManager: RequestManager<SpartanURL, SpartanError> {

    static var `default`: SpartanRequestManager = SpartanRequestManager()
    
    private var requestRetrier: SpartanRequestRetrier {
        return configuration.requestRetrier as! SpartanRequestRetrier
    }
    
    init() {
        let configuration = Configuration { (config) in
            config.ignoredErrorCodes = [-997, -999]
            config.requestAdapter = SpartanRequestAdapter()
            config.requestRetrier = SpartanRequestRetrier()
        }
        super.init(configuration: configuration)
        configuration.requestObserver = requestRetrier
    }

    func mapBoolArray(_ method: Alamofire.HTTPMethod,
                      url: SpartanURL,
                      success: (([Bool]) -> Void)?,
                      failure: ((SpartanError) -> Void)?) -> DataRequest {
        
        return makeRequest(.get, url: url).responseJSON { (response) in
            switch response.result {
            case .success:
                success?(response.result.value! as! [Bool])
            case .failure(let error):
                failure?(SpartanError(nsError: error as NSError))
            }
        }
    }
    
    public func mapObject<T: Mappable, E: SpartanError>(_ method: Alamofire.HTTPMethod,
                                                        url: SpartanURL,
                                                        returnCachedResponse: Bool,
                                                        parameters: Parameters? = nil,
                                                        keyPath: String? = nil,
                                                        encoding: ParameterEncoding = URLEncoding.default,
                                                        headers: HTTPHeaders? = nil,
                                                        success: ((T) -> Void)?,
                                                        failure: ((E) -> Void)?) -> DataRequest? {
        
        if returnCachedResponse, let url = URL(string: url.absolute) {
            
            let urlRequest = try! URLRequest(url: url, method: method, headers: headers)
            let encodedURLRequest = try! encoding.encode(urlRequest, with: parameters)
            if let resolvedEntity: T = cachedResponse(urlRequest: encodedURLRequest) {
                success?(resolvedEntity)
                return nil
            }
        }
        
        return mapObject(method,
                         url: url,
                         parameters: parameters,
                         keyPath: keyPath,
                         encoding: encoding,
                         headers: headers,
                         success: success,
                         failure: nil)
            .responseObject(keyPath: keyPath, completionHandler: { [unowned self] (response: DataResponse<T>) in
                switch response.result {
                case .success:
                    self.cache(response: response)
                    success?(response.result.value!)
                case .failure(let error):
                    let nsError = error as NSError
                    print(nsError.localizedDescription)
                    failure?(E(nsError: nsError))
                }
            })
    }
    
    private func cachedResponse<T: Mappable>(urlRequest: URLRequest) -> T? {
        if let response = URLCache.shared.cachedResponse(for: urlRequest),
            let jsonString = String.init(data: response.data, encoding: .utf8),
            let resolvedEntity = T(JSONString: jsonString)
        {
            print("🙃 SUCCESSFULLY returning cached response for \(urlRequest.description)")
            return resolvedEntity
        } else {
            print("🤨 FAILED to return cached response for \(urlRequest.description)")
            return nil
        }
    }
    
    private func cache<T: Mappable>(response: DataResponse<T>) {
        if let httpResponse = response.response, let data = response.data, let request = response.request {
            let cachedResponse = CachedURLResponse.init(response: httpResponse,
                                                        data: data,
                                                        userInfo: nil,
                                                        storagePolicy: .allowed)
            URLCache.shared.storeCachedResponse(cachedResponse, for: request)
        }
    }
}
