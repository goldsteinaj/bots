module Sample_2022_03_07 exposing (..)

import BotLab.SimpleBotFramework exposing (Location2d)


type alias ScenarioSinglePatternOnSampleImage =
    { imageFileBase64 : String
    , instanceLocations : List Location2d
    }


{-| Instances of the coin from training sample <https://github.com/Viir/bots/blob/9bd0f72551b5a927cb1b5bec907570d7ffc20033/implement/applications/elvenar/training-data/2022-03-07-elvenar-djvj-BTqe1xf.bmp>
-}
sample_2022_03_07_coins : List ScenarioSinglePatternOnSampleImage
sample_2022_03_07_coins =
    [ { imageFileBase64 = """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Km+eHFWFJWudIGidCD10GFaLNHejk+f6f9r6L2CLPVVzwuPhV5uYQ4+HPoyAP4d7NnZpMmZbN4VuPpiEKIVaOZWBM4JqKWtRKl5MIVhCMG9hGUo4KZiZGl9SG2deHmVdJ4J6MmxjT6ahecPGUm6KPV6AZrjXXKnLPG6TR4mtR4mtKVyQRY68Ra/cLHinZrXUU4akDCRPnLvBZKqrU5+aVYmCSoR7OYd5NG9jM29jMnxnMIRyNIhvLoFvLIBrMYh0NIp4NntxPoZ/JG5jH2hbGmRYHIJ4H4l/InBnLZaRMn5yTZqQktPQV3KJHDNdVISkddDrcNbxcNbxa8bnV6HJR8TyQ7jmKmKMLEZpjL7Hebm1R5eQPouDRoJ5OYJ2MId3MGpeMnJmOH1sM4p4PYd0QYh1NYRxKYBsL4VwLIFuKXRjLHVjJYmAGllLG3ZrESwdGUs+IWRZIEUzN39uU3xverGridjrNVh+LDleRFl6X6jGXazSXazSI2CNES5bRGuKmtHRcqegTI2LN35zNXxyLGpeMF9VM3VpL3lsK2RWM417M4x5KYBsLIFtKoBsMIZxMIZxLIdzK4NwNoNzLntrJXdnGlk4JJWDH4BVH3JHLIRVModZO5pwRKaMUaKVhMnEmsnPgqGwVFx2TVdzTVdziaa1osnSfLCvTZSRTpqUSZePNntxLHBjLGpeMnBkNH5xLGxfKFxPOJB+OIl4K3ppKXVkLntrMHdoMIBwL4NyNJGAPJB+KoRvJW5ZI458Glk4HWs+G2Q2IF01Il02KGQ/PcWRPaKBSKmQZb+lftG4icG4jtLIj93NeKuiYYiBVo2GTZmTO46JOpeNPn51MW5lLGtiT4aAVoqEUYR/OXFsOJiDOHxuKnppLH1sLoBvMIl3MHVmKW1bMIZ1Z5iRRJGAKnxnN6l6I042GUcmGUclL5JzIWc2I2o6IW5bJGRSLoBoNIdzPZyHR7ifTdG1Qol2RZqKUJeRRo6HOIB6NoeANo6DOHZtP31zNXVsPn51P392X5CLUIN+NYd2NpB9MoRyL31sMYJyMoh3MoR0MH1sLndmPYByNINyK3tpLGxbLWVTL4BeMpJpI2k9JnJFJ3VOGmFMGlZCKph3KH5gJ2JLN5l9MX9mRbGVQaSRO4iANntzM3RrNnpxPoJ5OXxzOXxzMHNpO3pzUIKCQH54T4SANY98MYBvMH1sOIdzNYZzLXpnLHhkNH5uOoByRXlsLHxsLHhpMHhsL2FVM3tlLXdiOIlzPZWLOIJxK3dqKWxeKFRBK2xWKm1XOIpzJm1cL3pvMI+CMXxzMXBoMXFpNnNqRoN6QoR+NXlxMXZtN3dxTH+ANntzQX97M4ZzMH1sMX9tOol1NYd2OJGDOJGDTol+OYBxMnxsKn1sLHprMHZpMHZpLHdoLHtsL3ltMHlvKoByLIF1M3xzLm5jQYyFQ392QoJ8OX52MIB4MJCDMXpxNXx1NXpzQX91QX91OHtzOHxzMHVsMHVsMHVsKXVsKXVsMnpoNH5sMod2MIt5MX1tMIBxMJOCMH1yMHhuMIJ1MIByMIF0MHxvMHhrRXlsKnlsMW9mMHFqMHxyLnpyLnpxLntxMH1zMn52NHNpLIB2QY2DPYmAKXVsL4uCLYV8NIJ/MIB7L31zMHFpL2tlL3FtLG5qMG1sMG1s"""
      , instanceLocations = [ { x = 24, y = 14 } ]
      }
    , { imageFileBase64 = """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PVNORHNrNWFWN3xrNINuOZN/OIp8PpWPTKy0gMTKibnFJUFqNFh+cLzYb9byb9byc9T1U5zFUcHrQ7jmHU99P1x7ir/KcMPISaqwOpOXMIGHLImNLY6SLJCTMHSHMXWJN4eaQ5OyR5e6Spq8TKHFSZa6xtnYe4iHMDk2Kjg1RnBrOm9zOIyANYt1NXhnOYB0PpiQU6SfZ7a3c8zXfaK4SVp4PEFjTXaVTYClTYClM12GLUduRmuKjdPaa8HDSba3PainM5mWLJOQK46NK4uNK4uNLXyHMHWJLX+IN42eQ5eySJa4R5O0SJW5ma+r7fTx7vXymrCrV3l0IDlEYXuASJKoNXJkNn5sOYFyO4R4RpiRUbCrYMPCldnbtu3yb4SZXG6FXG6Fl77JtubqgL+9TK2uQJ+eOp2ZNp+YLJWQLJONJYN/JYJ+JYJ+KIiDL4GQLIqQLIWMLZWYLJGTNZKdSZvAV3l0iKGcg52Y0d3aq766pLy9Q11lRICSSZewQIiSNHRnN35rPYh5RJuOSaKYWKyhcbOqf7+6gcnFgMrFeb+5arWsXqOdQZ2YOpCEM5GFLYuDJ4mEIH99JIKAJYJ+JYJ+KIiDK4SJLpOXK4GIK4aLLJGTKZCPMJCcRmFdWHJuUWxngJyYyNrX0Onm6P36d42IQ4GNR5SgQo+NMnZkOol6O5GAPZKAQ5qMRZeIR5iLR6GTRqGSRKGXP6GSP4+EOox7NIh4LIN5K4Z8KYuDKIZ+KImBKJONKI+HKISCKH58LH+LLX2LLYCMLIqNMYGPMoqWQU5LEB8cVmdjRVROaIeCT317lbWz8/vwqMnIQoiGNId2P4yBN4ZxMXRfPIh2QJOAOod3PIh5PJGFOoV3Oox9OI18M4p+L4N2LIB0KoR6KoJ5KYd+KIR7KJCLKJGLKJiTKJiTKJSQK42LK42LLoGMMoGQM36QL4CL7fTx1N3aiKOfQU1HTF5YW4SDhKalbqGns9LPQ4mJP4yBN4RzMHpmMnhiNn9qM3hkMHNgL25dLn5vMYV5L3dlMHRhMYNwL4N1LYV4LIR5K4h/KY+IKIuGK32ALHyCLH6EJIB+JIOAKY+ILJWQKYaFKIOAKYeFLIGLaZCLwdLM6/byssjFcpCNR1pTYXJsrfPwUImBVZaQMnZrLnBjMXBbOX1lLnRWJmRKJ1tIM3hlMHVhLm5bL31rL3JiL3lmMIZ4LId+LIyCKomCKYB9KIB/LH+EL3WFL3eGN4OYN4OYK46LLZGPK5KPKJGNKI2JKpCLX4iDX4iDo7y4vtTR5fTxqLSvqLOvP3ZuCDYsCCwfGkEvJ1xQFjYfNGtSEzcfHVI1EzgfIFI6J1tILGxSMnlkL25dL3toMoV2L4N3LIuBLI6FKYyGKYeCLJCKL3eGL4KIN4OYMICNJYN+IH10In12KH17KIuIKJiLT3FudJGNc5SPiK6sm7+83ebjy9XRGTMsGTMsH0U2FEwjIVc0IVU2I1o6FjYbGUsoF0smEzkZFTQbGjkjHEspMW9aMHhkNYl2MoJzLoZzLIt9K42CK4qCKo6HLJSPLJONLJWQLJWQLpiPLJWMLJKKLJCKLJKLK5GJYHx5SGZkb4+JU3lwfaWfhKKembGviaOeJzkzNVhNM3VOI2U2H1QxFT8dFUkhGE8nEzUXF0QhESgNGD8gHlsxH14yMG9VNYBsM4VxNIlzNI96Mo18Lol7LId8K4mALI2ELI6HLIuDLY+DLJGFLJCHLI+ILJOMK5CI7v3xSGZkeqCdc5mSteHhP21sVH173Pz4dYuHPGBYd7uyd7uyM39aG0wqDigKIYJHKK5jLLFvLLJvL65jJoBHLmlRNn9rNYBsNYBsM4BsMXhmMXlnM4VzMIJzL4Z0L39yLoB0Ln9xLoZ2L5mKLY+BL5OKMJyULZuURGtl7O/oaIaAepeSv9bUMkxELEU9cYeA5e7rZIZ+d6ujTX1rQ1tULD40LZRfHGk0HW83Hl4zJ4ZJHmhEI3JUK2lRMIlwM4BrNH5pLnhhLXNfNoJzO4N7OHxrO4mCMntwLnppL3tpL3loLoVzLYJyLoV3LYyBK4h+YIF7OGJboLaxV3lzvtXUYnlwTWVcW3Rsh5yTZIZ+d6ujNGFKd5yZlMDBETUUH3Y9IYRIKZBQJYBGETsOIWpJMIBsMXdkN4JxOIh4OYl4Oop/SpyjUKKwVKHDRY2VQYiEOoB1MXllMIBqMIJsL4VxMIp8LoByK4ByusrIVWdmkKinXXN2XXN25vXxU2RYGT4sPGVVWYF4cJSSLFQ2KVo8KVo7MWlTN21agaelGigaN2NYNnp0PldPKKakK6aiI5ONJqGeJqKgKp2cQ7TNPa/DZrnvXbjoV7roNZ+dMJuLMn9sMoJvMIFqL3dkL3xrLoBx2+vmb4B+kKmngp6dhqOitMW/lKScSnNkP2dYRWxdXIF4NV5DMGNHQ3dgPG9ZQXZknr/CNF1SJTwuQkU7MI+MJ6KgJp6aKKKdJ6KgJZmWLaOoQrHIPq/DPbLLQ7TRO7fJNrfDNLC1MaelMK6sOZaOOYFzMHxuL4BxgJCOChgaCxUaHSszFB8oEigYFTIfIkAvQGRWSG5gSnNjKlQ3Jlg5NmtSSYFuRYNsQGxeMlVLL1NDPV1KMHhqJZKIJp+cIJGLKrS2IpOPLLCxHpSMNrC8IaqpIaqpKqWkI7OpLKajLqajJbS1LLKvOomBMHtsL31wa42LChEVDxYVHy4wMEpTKVc7OIVbEh0NaJCHrOrpgby4RXRkIVM0MXpWRJtyNHlZGTssOU1ORoFsRbGFLYFfHWhRG4eCHZOPIpKNIpKNJKGcI6SdKrSvHYeAH5OMKa6pKq+qJZuVIJ+ZIaCaKpGNLKGgOZmWNINy"""
      , instanceLocations = [ { x = 17, y = 23 } ]
      }
    , { imageFileBase64 = """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"""
      , instanceLocations = [ { x = 24, y = 23 } ]
      }
    ]