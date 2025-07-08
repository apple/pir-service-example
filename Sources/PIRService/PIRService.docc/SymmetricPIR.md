# Symmetric PIR

Learn how to use Symmetric PIR in PIRService.

## Configuration

*Symmetric PIR* is a variant of PIR which guarantees that the client learns only the keyword-value pair that it requested, and is oblivious of other entries in the database.

To demonstrate Symmetric PIR, we will convert the NEURLFilter example to a Symmetric PIR use-case. Follow the set-up instructions in <doc:TestingInstructionsNEURLFilter> until <doc:TestingInstructionsNEURLFilter#Processing-the-dataset>. Symmetric PIR processes input data differently; informally, it additionally encrypts each database entry using a database encryption key. We can instruct `PIRProcessDatabase` to use a freshly generated encryption key by adding `symmetricPirArguments` to `url-config.json` we wrote in <doc:TestingInstructionsNEURLFilter#Processing-the-dataset>, as below.

```json
{
  "inputDatabase": "input.txtpb",
  "outputDatabase": "url-SHARD_ID.bin",
  "outputPirParameters": "url-SHARD_ID.params.txtpb",
  "rlweParameters": "n_4096_logq_27_28_28_logt_5",
  "sharding": {
    "entryCountPerShard": 50000
  },
  "symmetricPirArguments": {
      "outputDatabaseEncryptionKeyFilePath": "spir-encryption-key.txt"
  },
  "trialsPerShard": 5
}
```

Specifying `outputDatabaseEncryptionKeyFilePath` as above writes the newly generated encryption key to the given path. For more details on `symmetricPirArguments`, see [PIRProcessDatabase](https://swiftpackageindex.com/apple/swift-homomorphic-encryption/main/documentation/pirprocessdatabase#Fully-Oblivious-Symmetric-PIR)

Next, we have to instruct the service that this is a Symmetric PIR use-case and the database has been processed accordingly. We do this by modifying `service-config.json` we wrote in <doc:TestingInstructionsNEURLFilter#Running-the-service>. Simply add the `symmetricPirArguments` key as below, using the same path for database encryption key you specified in `url-config.json` above.

```json
{
  "users": [
    {
      "tier": "tier1",
      "tokens": ["AAAA"]
    },
    {
      "tier": "tier2",
      "tokens": ["BBBB", "CCCC"]
    }
  ],
  "usecases": [
    {
      "fileStem": "url",
      "shardCount": 1,
      "name": "com.example.apple-samplecode.SimpleURLFilter.url.filtering",
      "symmetricPirArguments": {
          "databaseEncryptionKeyFilePath": "spir-encryption-key.txt"
      }
    }
  ]
}
```

The rest of the steps remain the same as in <doc:TestingInstructionsNEURLFilter>.
