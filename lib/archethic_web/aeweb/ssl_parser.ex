defmodule ArchethicWeb.AEWeb.SSLParser do
  @moduledoc """
  SSLParser is a wrapper around Erlang's `:public_key` module to make it far more friendly. It automatically
  processes OIDs for most X509v3 extensions and subject fields.

  There are really only two functions of note - `parse_der` and `parse_pem`, which should have obvious functions.
  """

  require Logger

  @cert_regex ~r/^\-{5}BEGIN\sCERTIFICATE\-{5}\n(?<certificate>[^\-]+)\-{5}END\sCERTIFICATE\-{5}/
  @pubkey_schema Record.extract_all(from_lib: "public_key/include/OTP-PUB-KEY.hrl")

  @extended_key_usages %{
    {1, 3, 6, 1, 5, 5, 7, 3, 1} => "TLS Web server authentication",
    {1, 3, 6, 1, 5, 5, 7, 3, 2} => "TLS Web client authentication",
    {1, 3, 6, 1, 5, 5, 7, 3, 3} => "Code signing",
    {1, 3, 6, 1, 5, 5, 7, 3, 4} => "E-mail protection",
    {1, 3, 6, 1, 5, 5, 7, 3, 8} => "Timestamping",
    {1, 3, 6, 1, 5, 5, 7, 3, 9} => "OCSPstamping",
    {1, 3, 6, 1, 5, 5, 7, 3, 5} => "IP security end system",
    {1, 3, 6, 1, 5, 5, 7, 3, 6} => "IP security tunnel termination",
    {1, 3, 6, 1, 5, 5, 7, 3, 7} => "IP security user"
  }

  @authority_info_access_oids %{
    {1, 3, 6, 1, 5, 5, 7, 48, 1} => "OCSP - URI",
    {1, 3, 6, 1, 5, 5, 7, 48, 2} => "CA Issuers - URI"
  }

  @doc """
  Takes in a string (or charlist) and returns a map of the parsed certificate

  ## Examples

      # Pass in a binary (from Base.decode64, or some other source)
      iex(1)> EasySSL.parse_pem("-----BEGIN CERTIFICATE-----\\nMII...")
      %{
        extensions: %{
          authorityInfoAccess:
            "CA Issuers - URI:http://certificates.godaddy.com/repository/gd_intermediate.crt\\nOCSP - URI:http://ocsp.godaddy.com/\\n",
          authorityKeyIdentifier:
            "keyid:FD:AC:61:32:93:6C:45:D6:E2:EE:85:5F:9A:BA:E7:76:99:68:CC:E7\\n",
          basicConstraints: "CA:FALSE",
          certificatePolicies:
            "Policy: 2.16.840.1.114413.1.7.23.1\\n  CPS: http://certificates.godaddy.com/repository/",
          crlDistributionPoints: "Full Name:\\n URI:http://crl.godaddy.com/gds1-90.crl",
          extendedKeyUsage: "TLS Web server authentication, TLS Web client authentication",
          keyUsage: "Digital Signature, Key Encipherment",
          subjectAltName: "DNS:acaline.com, DNS:www.acaline.com",
          subjectKeyIdentifier: "E6:61:14:4E:5A:4B:51:0C:4E:6C:5E:3C:79:61:65:D4:BD:64:94:BE"
        },
        fingerprint: "FA:BE:B5:9B:ED:C2:2B:42:7E:B1:45:C8:9A:8A:73:16:4A:A0:10:09",
        issuer: %{
          C: "US",
          CN: "Go Daddy Secure Certification Authority",
          L: "Scottsdale",
          O: "GoDaddy.com, Inc.",
          OU: "http://certificates.godaddy.com/repository",
          ST: "Arizona",
          aggregated:
            "/C=US/CN=Go Daddy Secure Certification Authority/L=Scottsdale/O=GoDaddy.com, Inc./OU=http://certificates.godaddy.com/repository/ST=Arizona",
          emailAddress: nil
        },
        not_after: 1_398_523_877,
        not_before: 1_366_987_877,
        serial_number: "27ACAE30B9F323",
        signature_algorithm: "sha, rsa",
        subject: %{
          C: nil,
          CN: "www.acaline.com",
          L: nil,
          O: nil,
          OU: "Domain Control Validated",
          ST: nil,
          aggregated: "/CN=www.acaline.com/OU=Domain Control Validated",
          emailAddress: nil
        }
      }
  """
  def parse_pem(cert_charlist) when is_list(cert_charlist),
    do: cert_charlist |> to_string() |> parse_pem()

  def parse_pem(cert_pem) do
    case Regex.named_captures(@cert_regex, cert_pem) do
      nil ->
        {:error, "Unable to parse PEM. Is the certificate well formed?"}

      %{"certificate" => certificate} ->
        certificate |> String.replace("\n", "") |> Base.decode64!() |> parse_der()
    end
  end

  defp parse_der(certificate_der) do
    cert = certificate_der |> :public_key.pkix_decode_cert(:otp) |> get_field(:tbsCertificate)

    subject = parse_rdnsequence(cert, :subject)

    Map.new()
    |> Map.put(:fingerprint, fingerprint_cert(certificate_der))
    |> Map.put(:serial_number, cert |> get_field(:serialNumber) |> Integer.to_string(16))
    |> Map.put(:signature_algorithm, parse_signature_algo(cert))
    |> Map.put(:subject, subject)
    |> Map.put(:issuer, parse_rdnsequence(cert, :issuer))
    |> Map.put(:extensions, parse_extensions(cert))
    |> Map.put(:all_domains, get_all_domain_names(cert, subject))
    |> Map.merge(parse_expiry(cert))
  end

  defp get_all_domain_names(cert, %{CN: cn_name}) do
    domain_names = if cn_name == nil, do: MapSet.new(), else: MapSet.new([cn_name])

    cert
    |> get_field(:extensions)
    |> Enum.reduce(domain_names, fn
      {:Extension, {2, 5, 29, 17}, _critical, san_entries}, domain_names ->
        san_entries
        |> Keyword.get_values(:dNSName)
        |> Enum.reduce(domain_names, fn dns_name, acc -> MapSet.put(acc, to_string(dns_name)) end)

      _, acc ->
        acc
    end)
    |> MapSet.to_list()
  end

  defp get_field(record, field) do
    record_type = elem(record, 0)

    idx =
      @pubkey_schema
      |> Keyword.fetch!(record_type)
      |> Keyword.keys()
      |> Enum.find_index(&(&1 == field))

    elem(record, idx + 1)
  end

  defp fingerprint_cert(certificate) do
    :sha
    |> :crypto.hash(certificate)
    |> Base.encode16()
    |> String.to_charlist()
    |> Enum.chunk_every(2, 2, :discard)
    |> Enum.join(":")
  end

  defp parse_expiry(cert) do
    {:Validity, not_before, not_after} = get_field(cert, :validity)
    not_before = clean_time(not_before)
    not_after = clean_time(not_after)

    %{
      :not_before => not_before |> to_generalized_time() |> asn1_to_epoch(),
      :not_after => not_after |> to_generalized_time() |> asn1_to_epoch()
    }
  end

  defp clean_time(time_tuple) do
    {type, time_charlist} = time_tuple

    output =
      time_charlist
      |> to_string()
      |> String.split("+")
      |> List.first()
      |> then(fn foo ->
        last = String.last(foo)

        case last do
          "Z" -> foo
          _ -> foo <> "Z"
        end
      end)
      |> to_charlist()

    {type, output}
  end

  defp to_generalized_time({:generalTime, time}), do: time

  defp to_generalized_time({:utcTime, time}) do
    year = time |> Enum.take(2) |> List.to_integer()
    prefix = if year >= 50, do: ~c"19", else: ~c"20"
    prefix ++ time
  end

  defp asn1_to_epoch(asn1_time) do
    {year, rest} = Enum.split(asn1_time, 4)

    date =
      case Enum.chunk_every(rest, 2) do
        [month, day, hour, minute, second, ~c"Z"] ->
          [year, month, day, hour, minute, second]

        [month, day, hour, minute, ~c"Z"] ->
          [year, month, day, hour, minute, ~c"00"]

        _ ->
          Logger.error("Unhandled ASN1 time structure - #{asn1_time}}")
          nil
      end

    date_args = Enum.map(date, &(&1 |> to_string() |> String.to_integer()))

    case apply(NaiveDateTime, :new, date_args) do
      {:ok, ~N[9999-12-31 23:59:59]} ->
        :no_expiration

      {:ok, datetime} ->
        datetime |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()

      _ ->
        Logger.error("Unhandled ASN1 time structure - #{date_args}}")
        nil
    end
  end

  defp parse_signature_algo(cert) do
    cert
    |> get_field(:signature)
    |> get_field(:algorithm)
    |> :public_key.pkix_sign_types()
    |> Tuple.to_list()
    |> Enum.map_join(", ", &Atom.to_string/1)
  end

  defp parse_rdnsequence(cert, field) do
    rdnsequence = %{
      :CN => nil,
      :C => nil,
      :L => nil,
      :ST => nil,
      :O => nil,
      :OU => nil,
      :emailAddress => nil
    }

    {:rdnSequence, rdnsequence_attribute} = get_field(cert, field)

    rdnsequence =
      rdnsequence_attribute
      |> List.flatten()
      |> Enum.reduce(
        rdnsequence,
        fn {:AttributeTypeAndValue, oid, attribute_value}, rdnsequence ->
          case parse_oid(oid) do
            nil -> rdnsequence
            attr -> Map.put(rdnsequence, attr, coerce_to_string(attribute_value))
          end
        end
      )

    Map.put(rdnsequence, :aggregated, aggregate_rdnsequence(rdnsequence))
  end

  defp parse_oid({2, 5, 4, 3}), do: :CN
  defp parse_oid({2, 5, 4, 6}), do: :C
  defp parse_oid({2, 5, 4, 7}), do: :L
  defp parse_oid({2, 5, 4, 8}), do: :ST
  defp parse_oid({2, 5, 4, 10}), do: :O
  defp parse_oid({2, 5, 4, 11}), do: :OU
  defp parse_oid({1, 2, 840, 113_549, 1, 9, 1}), do: :emailAddress
  defp parse_oid(_), do: nil

  defp parse_crl_distribution_points(crl_distribution_points)
       when is_binary(crl_distribution_points) do
    :public_key.der_decode(:CRLDistributionPoints, crl_distribution_points)
  end

  defp parse_crl_distribution_points(crl_distribution_points) do
    crl_distribution_points
  end

  defp coerce_to_string({:printableString, string}), do: to_string(string)
  defp coerce_to_string({:utf8String, string}), do: to_string(string)
  defp coerce_to_string({:teletexString, string}), do: to_string(string)
  defp coerce_to_string(list) when is_list(list), do: to_string(list)

  defp aggregate_rdnsequence(rdnsequence) do
    rdnsequence
    |> Enum.filter(fn {_, v} -> v != nil end)
    |> Enum.map_join("/", fn {k, v} -> "#{k}=#{v}" end)
    |> String.replace_prefix("", "/")
  end

  defp parse_extension({1, 3, 6, 1, 5, 5, 7, 1, 1}, authority_info_access) do
    value =
      authority_info_access
      |> Enum.filter(&match?({:AccessDescription, _, {:uniformResourceIdentifier, _}}, &1))
      |> Enum.map_join("\n", fn {:AccessDescription, oid, {:uniformResourceIdentifier, url}} ->
        "#{@authority_info_access_oids[oid]}:#{url}"
      end)
      |> String.replace_suffix("", "\n")

    {:authorityInfoAccess, value}
  end

  defp parse_extension({1, 3, 6, 1, 4, 1, 11_129, 2, 4, 2}, sct_data) do
    {:ctlSignedCertificateTimestamp, Base.url_encode64(sct_data)}
  end

  defp parse_extension({1, 3, 6, 1, 4, 1, 11_129, 2, 4, 3}, _) do
    {:ctlPoisonByte, true}
  end

  defp parse_extension({2, 5, 29, 14}, subject_key_identifier) do
    value =
      subject_key_identifier
      |> Base.encode16()
      |> String.to_charlist()
      |> Enum.chunk_every(2, 2, :discard)
      |> Enum.join(":")

    {:subjectKeyIdentifier, value}
  end

  defp parse_extension({2, 5, 29, 15}, key_usage) do
    {:keyUsage, join_usage_types(key_usage)}
  end

  defp parse_extension({2, 5, 29, last_id}, san_entries) when last_id in [17, 18] do
    used_sans = [:dNSName, :uniformResourceIdentifier, :rfc822Name, :iPAddress]

    value =
      san_entries
      |> Enum.filter(fn {san, _} -> Enum.member?(used_sans, san) end)
      |> Enum.map_join(", ", fn
        {:dNSName, dns_name} -> "DNS:#{dns_name}"
        {:uniformResourceIdentifier, identifier} -> "URI:#{identifier}"
        {:rfc822Name, identifier} -> "RFC 822Name:#{identifier}"
        {:iPAddress, ip} -> "IP:#{ip_to_string(ip)}"
      end)

    key = if last_id == 17, do: :subjectAltName, else: :issuerAltName

    {key, value}
  end

  defp parse_extension({2, 5, 29, 19}, {:BasicConstraints, is_ca, _max_pathlen}) do
    value = if is_ca, do: "CA:TRUE", else: "CA:FALSE"
    {:basicConstraints, value}
  end

  defp parse_extension({2, 5, 29, 31}, crl_distribution_points) do
    value =
      crl_distribution_points
      |> parse_crl_distribution_points()
      |> Enum.filter(
        &match?({:DistributionPoint, {:fullName, _}, :asn1_NOVALUE, :asn1_NOVALUE}, &1)
      )
      |> Enum.map_join("Full Name:\n", fn {_, {_, crls}, _, _} ->
        Enum.map_join("\n", crls, fn
          {:uniformResourceIdentifier, uri} -> " URI:#{uri}"
          {:rfc822Name, identifier} -> " RFC 822 Name: #{identifier}"
          {:directoryName, _rdn_sequence} -> ""
        end)
      end)

    {:crlDistributionPoints, value}
  end

  defp parse_extension({2, 5, 29, 32}, policy_entries) do
    value =
      policy_entries
      |> List.flatten()
      |> Enum.map_join("\n", fn
        {:PolicyInformation, oid, :asn1_NOVALUE} ->
          "Policy: #{oid |> Tuple.to_list() |> Enum.join(".")}"

        {:PolicyInformation, oid, policy_information} ->
          oid_string =
            oid |> Tuple.to_list() |> Enum.join(".") |> String.replace_prefix("", "Policy: ")

          messages =
            Enum.map(policy_information, fn
              {:PolicyQualifierInfo, {1, 3, 6, 1, 5, 5, 7, 2, 1}, cps_data} ->
                cps_data
                |> to_charlist()
                |> Enum.drop(2)
                |> to_string()
                |> String.replace_prefix("", "  CPS: ")

              {:PolicyQualifierInfo, {1, 3, 6, 1, 5, 5, 7, 2, 2}, user_notice_data} ->
                <<_::binary-size(8), user_notice::binary>> = user_notice_data

                user_notice
                |> String.codepoints()
                |> Enum.filter(&String.printable?/1)
                |> Enum.join("")
                |> String.replace_prefix("", "  User Notice: ")
            end)

          [oid_string | messages]
      end)

    {:certificatePolicies, value}
  end

  defp parse_extension({2, 5, 29, 35}, {:AuthorityKeyIdentifier, :asn1_NOVALUE, _, _}), do: nil

  defp parse_extension({2, 5, 29, 35}, {:AuthorityKeyIdentifier, authority_key_identifier, _, _}) do
    value =
      authority_key_identifier
      |> Base.encode16()
      |> String.to_charlist()
      |> Enum.chunk_every(2, 2, :discard)
      |> Enum.join(":")
      |> String.replace_prefix("", "keyid:")
      |> String.replace_suffix("", "\n")

    {:authorityKeyIdentifier, value}
  end

  defp parse_extension({2, 5, 29, 37}, extended_key_usage) do
    {:extendedKeyUsage, Enum.map_join(extended_key_usage, ", ", &@extended_key_usages[&1])}
  end

  defp parse_extension(_, _), do: :extra

  defp parse_extensions(cert) do
    case get_field(cert, :extensions) do
      :asn1_NOVALUE -> %{}
      extensions -> reduce_extentions(extensions)
    end
  end

  defp reduce_extentions(extensions) do
    Enum.reduce(extensions, %{}, fn {:Extension, oid, _, payload}, acc ->
      case parse_extension(oid, payload) do
        nil ->
          acc

        {key, value} ->
          Map.put(acc, key, value)

        :extra ->
          value = oid |> Tuple.to_list() |> Enum.join(".")
          Map.update(acc, :extra, [value], &[value | &1])
      end
    end)
  end

  defp ip_to_string(ip) do
    ip |> :binary.bin_to_list() |> Enum.map_join(".", &to_string/1)
  end

  defp join_usage_types(key_usage) do
    Enum.map_join(key_usage, ", ", &camel_to_spaces/1)
  end

  defp camel_to_spaces(atom) do
    atom
    |> Atom.to_charlist()
    |> Enum.reduce([], fn char, charlist ->
      charlist = [char | charlist]

      if char in 65..90 do
        List.insert_at(charlist, 1, ~c" ")
      else
        charlist
      end
    end)
    |> Enum.reverse()
    |> to_string()
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
