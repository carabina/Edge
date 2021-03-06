//
//  IOStream.swift
//  Edge
//
//  Created by Tyler Fleming Cloutier on 5/1/16.
//
//

import Dispatch
import Reflex
import POSIX
import POSIXExtensions
#if os(Linux)
    import Glibc
    let empty_off_t = Glibc.off_t()
    let INT32_MAX = Glibc.INT32_MAX
#else
    import Darwin
    let empty_off_t = Darwin.off_t()
    let INT32_MAX = Darwin.INT32_MAX
#endif

public protocol WritableIOStream: class {
    
    var fd: POSIXExtensions.FileDescriptor { get }
    
    var channel: DispatchIO { get }
    
    func write(buffer: [UInt8]) -> ColdSignal<[UInt8], SystemError>

}

public extension WritableIOStream {
    
    func write(buffer: [UInt8]) -> ColdSignal<[UInt8], SystemError> {
        return ColdSignal { observer in
            let writeChannel = DispatchIO(
                type: .stream,
                io: self.channel,
                queue: .main
            ) { error in
                if let systemError = SystemError(errorNumber: error) {
                    observer.sendFailed(systemError)
                }
            }
            
            buffer.withUnsafeBufferPointer { buffer in
                
                // Allocate dispatch data
                // TODO: This does not seem right.
                // Work around crash for now.
                let dispatchData = DispatchData(
                    bytesNoCopy: buffer,
                    deallocator: .custom(nil, { })
                )
                
                // Schedule write operation
                writeChannel.write(offset: empty_off_t, data: dispatchData, queue: .main) { done, data, error in
                    
                    if let systemError = SystemError(errorNumber: error) {
                        // If there was an error emit the error.
                        observer.sendFailed(systemError)
                    }
                    
                    if let data = data, !data.isEmpty {
                        // Get unwritten data
                        data.enumerateBytes { (buffer, byteIndex, stop) in
                            observer.sendNext(Array(buffer))
                        }
                    }
                    
                    if done {
                        if error == 0 {
                            // If the done param is set and there is no error,
                            // all data has been written, emit writing end.
                            // DO NOT emit end otherwise!
                            observer.sendCompleted()
                        } else {
                            // Must be an unrecoverable error, close the channel.
                            // TODO: Maybe don't close if you want half-open channel
                            // NOTE: This will be done by onCompleted or onError
                            // dispatch_io_close(self.channel, 0)
                        }
                    }
                }
            }
            return ActionDisposable {
                writeChannel.close()
            }
        }
    }
}


public protocol ReadableIOStream: class {
    
    var fd: POSIXExtensions.FileDescriptor { get }
    
    var channel: DispatchIO { get }

    func read(minBytes: Int) -> ColdSignal<[UInt8], SystemError>
    
}

public extension ReadableIOStream {
    
    func read(minBytes: Int = 1) -> ColdSignal<[UInt8], SystemError> {
        
        return ColdSignal { observer in
            
            let readChannel = DispatchIO(type: .stream, io: self.channel, queue: .main) { error in
                if let systemError = SystemError(errorNumber: error) {
                    observer.sendFailed(systemError)
                }
            }
            
            readChannel.setLimit(lowWater: minBytes)
            readChannel.read(offset: empty_off_t, length: size_t(INT32_MAX), queue: .main) { done, data, error in
                
                if let systemError = SystemError(errorNumber: error) {
                    // If there was an error emit the error.
                    observer.sendFailed(systemError)
                }
                
                // Deliver data if it is non-empty
                if let data = data, !data.isEmpty {
                    data.enumerateBytes { (buffer, byteIndex, stop) in
                        observer.sendNext(Array(buffer))
                    }
                }
                
                if done {
                    if error == 0 {
                        // If the done param is set and there is no error,
                        // all data has been read, emit end.
                        // DO NOT emit end otherwise!
                        observer.sendCompleted()
                    }
                    
                    // It's done close the channel
                    // TODO: Maybe don't close if you want half-open channel
                    // NOTE: This will be done by onCompleted or onError
                    // dispatch_io_close(readChannel, 0)
                }
            }
            return ActionDisposable {
                readChannel.close()
            }
        }
    }
}
